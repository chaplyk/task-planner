import 'package:cloud_firestore/cloud_firestore.dart';

import 'collections.dart';
import 'llm/emoji.dart';
import 'models/recurrence.dart';
import 'notifications.dart';

typedef RoutineDoc = DocumentSnapshot<Map<String, dynamic>>;

// Writes go through [sendWrite] (see reminders_repo.dart): notification work must not wait for the server.

/// Routine ids double as notification ids. Reminder ids count seconds since 2026 from 0;
/// routines start at one billion, so the two can never collide and both fit in an int32.
const _idOffset = 1000000000;

/// One time a routine was marked done or skipped.
class RoutineEvent {
  const RoutineEvent({required this.at, required this.skipped, this.due});

  final DateTime at;
  final bool skipped;

  /// When that cycle was due, to tell on time from late. Missing for entries made before history existed.
  final DateTime? due;

  /// How late it was done or skipped; null when on time or unknown.
  Duration? get late {
    if (due == null) return null;
    final d = at.difference(due!);
    return d.inMinutes >= 1 ? d : null;
  }

  static RoutineEvent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'];
    if (at is! Timestamp) return null;
    final due = raw['due'];
    return RoutineEvent(at: at.toDate(), skipped: raw['action'] == 'skip', due: due is Timestamp ? due.toDate() : null);
  }
}

/// History entries kept per routine; older ones are dropped (an hourly routine would otherwise grow without end).
const _maxHistory = 200;

/// A routine as stored in Firestore, read defensively.
class Routine {
  Routine(this.id, Map<String, dynamic> data)
      : name = data['name'] as String? ?? '',
        emoji = data['emoji'] as String? ?? fallbackEmoji,
        recurrence = Recurrence.tryParse(data) ?? const Recurrence(every: 1, unit: 'day'),
        nextDue = (data['nextDue'] as Timestamp?)?.toDate() ?? DateTime.now(),
        periodStart = (data['periodStart'] as Timestamp?)?.toDate() ??
            (data['createdAt'] as Timestamp?)?.toDate() ??
            DateTime.now(),
        lastDone = (data['lastDone'] as Timestamp?)?.toDate(),
        history = _history(data);

  /// Newest first. A routine done before history was recorded shows its last completion.
  static List<RoutineEvent> _history(Map<String, dynamic> data) {
    final raw = data['history'];
    final events = [
      if (raw is List)
        for (final e in raw) ?RoutineEvent.tryParse(e),
    ]..sort((a, b) => b.at.compareTo(a.at));
    final lastDone = data['lastDone'];
    if (events.isEmpty && lastDone is Timestamp) events.add(RoutineEvent(at: lastDone.toDate(), skipped: false));
    return events;
  }

  final String id;
  final String name;
  final String emoji;
  final Recurrence recurrence;
  final DateTime nextDue;
  final DateTime periodStart;
  final DateTime? lastDone;
  final List<RoutineEvent> history;

  int get notificationId => int.parse(id);

  bool isDue(DateTime now) => !nextDue.isAfter(now);

  /// Due by the end of [now]'s day (including overdue): what Home shows.
  bool isDueToday(DateTime now) => nextDue.isBefore(DateTime(now.year, now.month, now.day + 1));
}

Future<void> _schedule(int id, String emoji, String name, DateTime due) =>
    scheduleNotification(id, '$emoji $name'.trim(), due);

/// Creates a routine, schedules its first notification and picks an emoji for it.
/// Returns the routine id. Without [firstDue] it is first due one interval from now.
/// Pass [emoji] to keep the user's pick instead of choosing one.
Future<String> saveRecurring(String name, Recurrence recurrence, {DateTime? firstDue, String? emoji}) async {
  final now = DateTime.now();
  final id = '${now.difference(DateTime.utc(2026)).inSeconds + _idOffset}';
  final due = firstDue != null && firstDue.isAfter(now) ? firstDue : recurrence.advance(now);
  final chosen = emoji ?? keywordEmoji(name);
  final ref = recurringCollection().doc(id);
  sendWrite(ref.set({
    'name': name,
    'emoji': chosen,
    ...recurrence.toMap(),
    'nextDue': Timestamp.fromDate(due),
    'periodStart': Timestamp.fromDate(now),
    'lastDone': null,
    'createdAt': Timestamp.fromDate(now),
  }));
  await _schedule(int.parse(id), chosen, name, due);
  if (emoji == null) _refineEmoji(ref, name, chosen, due);
  return id;
}

/// Asks AI for a better emoji in the background and keeps the notification text in step.
Future<void> _refineEmoji(DocumentReference<Map<String, dynamic>> ref, String name, String current, DateTime due) async {
  final emoji = await suggestEmoji(name, task: true);
  if (emoji == current) return;
  sendWrite(ref.update({'emoji': emoji}));
  await _schedule(int.parse(ref.id), emoji, name, due);
}

/// Marks this cycle done and moves to the next one. Returns the old fields for [restoreRecurring].
Future<Map<String, dynamic>> completeRecurring(RoutineDoc doc) async {
  final r = Routine(doc.id, doc.data() ?? const {});
  final now = DateTime.now();
  final next = r.recurrence.nextDueAfterDone(prevDue: r.nextDue, doneAt: now);
  return _moveTo(doc, r, next, now: now, skipped: false, lastDone: now);
}

/// Skips this cycle without marking it done.
Future<Map<String, dynamic>> skipRecurring(RoutineDoc doc) async {
  final r = Routine(doc.id, doc.data() ?? const {});
  final now = DateTime.now();
  // A skip always moves along the schedule, even for "after I finish" routines.
  final next = r.recurrence.withMode(Recurrence.modeFixed).nextDueAfterDone(prevDue: r.nextDue, doneAt: now);
  return _moveTo(doc, r, next, now: now, skipped: true, lastDone: r.lastDone);
}

Future<Map<String, dynamic>> _moveTo(
  RoutineDoc doc,
  Routine r,
  DateTime next, {
  required DateTime now,
  required bool skipped,
  required DateTime? lastDone,
}) async {
  final data = doc.data() ?? const {};
  final entry = {
    'at': Timestamp.fromDate(now),
    'action': skipped ? 'skip' : 'done',
    'due': Timestamp.fromDate(r.nextDue),
  };
  final stored = data['history'];
  // Appended atomically, so an entry written from another screen a moment ago is kept;
  // only a full history is rewritten, keeping the newest entries.
  final Object history = stored is List && stored.length >= _maxHistory
      ? [...stored.skip(stored.length - _maxHistory + 1), entry]
      : FieldValue.arrayUnion([entry]);
  final previous = {
    'nextDue': data['nextDue'],
    'periodStart': data['periodStart'],
    'lastDone': data['lastDone'],
    'history': FieldValue.arrayRemove([entry]),
  };
  sendWrite(doc.reference.update({
    'nextDue': Timestamp.fromDate(next),
    'periodStart': Timestamp.fromDate(now),
    'lastDone': lastDone == null ? null : Timestamp.fromDate(lastDone),
    'history': history,
  }));
  await cancelNotification(r.notificationId);
  await _schedule(r.notificationId, r.emoji, r.name, next);
  return previous;
}

/// Undoes [completeRecurring] / [skipRecurring] with the fields they returned.
Future<void> undoMove(RoutineDoc doc, Map<String, dynamic> previous) async {
  sendWrite(doc.reference.update(previous));
  final r = Routine(doc.id, {...?doc.data(), ...previous});
  await cancelNotification(r.notificationId);
  await _schedule(r.notificationId, r.emoji, r.name, r.nextDue);
}

/// Changes name, emoji, interval and (optionally) the next due time.
Future<void> updateRecurring(
  RoutineDoc doc, {
  required String name,
  required String emoji,
  required Recurrence recurrence,
  DateTime? nextDue,
}) async {
  final r = Routine(doc.id, doc.data() ?? const {});
  final intervalChanged = r.recurrence.every != recurrence.every || r.recurrence.unit != recurrence.unit;
  // A new interval restarts the cycle from its last start, unless the user picked a time.
  final due = nextDue ?? (intervalChanged ? recurrence.advance(r.periodStart) : r.nextDue);
  sendWrite(doc.reference.update({
    'name': name,
    'emoji': emoji,
    ...recurrence.toMap(),
    'nextDue': Timestamp.fromDate(due),
  }));
  await cancelNotification(r.notificationId);
  await _schedule(r.notificationId, emoji, name, due);
}

/// Deletes a routine. Returns its data so it can be restored with [restoreRecurring].
Future<Map<String, dynamic>?> deleteRecurring(RoutineDoc doc) async {
  final data = doc.data();
  sendWrite(doc.reference.delete());
  await cancelNotification(int.parse(doc.id));
  return data;
}

Future<void> deleteRecurringById(String id) async {
  sendWrite(recurringCollection().doc(id).delete());
  await cancelNotification(int.parse(id));
}

Future<void> restoreRecurring(String id, Map<String, dynamic> data) async {
  sendWrite(recurringCollection().doc(id).set(data));
  final r = Routine(id, data);
  await _schedule(r.notificationId, r.emoji, r.name, r.nextDue);
}

/// Re-creates every routine's pending notification (they are lost on reinstall or a new device).
Future<void> rescheduleAllRecurring() async {
  for (final doc in (await recurringCollection().get()).docs) {
    final r = Routine(doc.id, doc.data());
    await _schedule(r.notificationId, r.emoji, r.name, r.nextDue);
  }
}
