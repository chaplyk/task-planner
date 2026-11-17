import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'activity_watch.dart';
import 'calendar_sync.dart';
import 'collections.dart';
import 'llm/emoji.dart';
import 'models/reminder.dart';
import 'notifications.dart';

typedef ReminderDoc = DocumentSnapshot<Map<String, dynamic>>;

// Writes here go through [sendWrite]: the notification work that follows must not wait
// for the server, or it would never happen while offline.

/// Saves a new reminder and schedules its notification. Returns the reminder id
/// (seconds since 2026, also used as the notification id).
///
/// A reminder without an emoji gets a keyword guess at once and an AI pick in the background,
/// unless [emojiLater] says a follow-up refinement will set it (see [updateReminderText]).
Future<int> saveReminder(Reminder reminder, {bool emojiLater = false}) async {
  final id = DateTime.now().difference(DateTime.utc(2026)).inSeconds;
  final auto = reminder.emoji == null;
  final saved = auto ? reminder.withEmoji(keywordEmoji(reminder.summary)) : reminder;
  final ref = remindersCollection().doc('$id');
  sendWrite(ref.set(saved.toMap()));
  await _schedule(id, reminder.summary, reminder.triggerType, reminder.from);
  unawaited(syncReminderToCalendar('$id', saved.toMap()));
  if (auto && !emojiLater) {
    suggestEmoji(reminder.summary, task: true).then((e) {
      if (e != saved.emoji) sendWrite(ref.update({'emoji': e}));
    });
  }
  return id;
}

// Reminders already being given an emoji, so a rebuild does not ask twice.
final _backfilling = <String>{};

/// Gives an emoji to reminders saved before emoji existed (one AI call each, once).
void backfillEmoji(Iterable<ReminderDoc> docs) {
  for (final doc in docs) {
    final data = doc.data();
    final emoji = data?['emoji'];
    if (data == null || (emoji is String && emoji.isNotEmpty) || !_backfilling.add(doc.id)) continue;
    suggestEmoji(data['summary'] as String? ?? '', task: true)
        .then((e) => sendWrite(doc.reference.update({'emoji': e})));
  }
}

/// Whether the user has never created a reminder.
Future<bool> isFirstReminder() async =>
    (await remindersCollection().limit(1).get()).docs.isEmpty;

/// When a stored reminder starts. Documents saved before ranges existed keep it in "when".
DateTime? reminderStart(Map<String, dynamic> data) {
  final v = data['from'] ?? data['when'];
  return v is Timestamp ? v.toDate() : null;
}

/// When a stored reminder ends, if it is a range.
DateTime? reminderEnd(Map<String, dynamic> data) {
  final v = data['to'];
  return v is Timestamp ? v.toDate() : null;
}

Reminder reminderFromDoc(ReminderDoc doc) {
  final data = doc.data() ?? const {};
  return Reminder(
    summary: data['summary'] ?? '',
    from: reminderStart(data),
    to: reminderEnd(data),
    condition: data['condition'],
    transcript: data['transcript'],
    triggerType: data['triggerType'] ?? 'none',
    activity: data['activity'],
    location: data['location'],
    locationEvent: data['locationEvent'],
    category: data['category'],
    list: data['list'],
    confidence: (data['confidence'] as num?)?.toDouble(),
    emoji: data['emoji'] as String?,
  );
}

/// Replaces the editable fields of an existing reminder and reschedules it.
Future<void> updateReminder(ReminderDoc doc, Reminder updated) async {
  sendWrite(doc.reference.update({
    'summary': updated.summary,
    'from': updated.from == null ? null : Timestamp.fromDate(updated.from!),
    'to': updated.to == null ? null : Timestamp.fromDate(updated.to!),
    // Moves documents saved before ranges existed to the new keys.
    'when': FieldValue.delete(),
    'condition': updated.condition,
    'triggerType': updated.triggerType,
    'activity': updated.activity,
    'location': updated.location,
    'locationEvent': updated.locationEvent,
    'category': updated.category,
    'list': updated.list,
    'emoji': ?updated.emoji,
    'notified': false,
  }));
  final id = int.parse(doc.id);
  await cancelNotification(id);
  await _schedule(id, updated.summary, updated.triggerType, updated.from);
  unawaited(syncReminderToCalendar(doc.id, {
    'summary': updated.summary,
    'from': updated.from == null ? null : Timestamp.fromDate(updated.from!),
    'to': updated.to == null ? null : Timestamp.fromDate(updated.to!),
    'triggerType': updated.triggerType,
    'status': doc.data()?['status'] ?? 0,
  }));
}

Future<void> completeReminder(ReminderDoc doc) async {
  sendWrite(doc.reference.update({'status': 1, 'completedAt': Timestamp.now()}));
  await cancelNotification(int.parse(doc.id));
  unawaited(syncReminderToCalendar(doc.id, null));
}

Future<void> reopenReminder(ReminderDoc doc) async {
  sendWrite(doc.reference.update({'status': 0, 'completedAt': null, 'notified': false}));
  final r = reminderFromDoc(doc);
  await _schedule(int.parse(doc.id), r.summary, r.triggerType, r.from);
  unawaited(syncReminderToCalendar(doc.id, {...?doc.data(), 'status': 0}));
}

/// Clears the "notified" flag so an activity or place reminder can fire again.
Future<void> clearNotified(ReminderDoc doc) async {
  sendWrite(doc.reference.update({'notified': false}));
  if (doc.data()?['triggerType'] == 'location') await startWatch();
}

/// Deletes a reminder. Returns its data so it can be restored with [restoreReminder].
Future<Map<String, dynamic>?> deleteReminder(ReminderDoc doc) async {
  final data = doc.data();
  sendWrite(doc.reference.delete());
  await cancelNotification(int.parse(doc.id));
  unawaited(syncReminderToCalendar(doc.id, null));
  return data;
}

Future<void> deleteReminderById(int id) async {
  sendWrite(remindersCollection().doc('$id').delete());
  await cancelNotification(id);
  unawaited(syncReminderToCalendar('$id', null));
}

Future<void> restoreReminder(String id, Map<String, dynamic> data) async {
  sendWrite(remindersCollection().doc(id).set(data));
  await _schedule(int.parse(id), data['summary'] ?? '', data['triggerType'], reminderStart(data));
  unawaited(syncReminderToCalendar(id, data));
}

/// Sets up what makes a reminder fire: a scheduled notification for a time, or the
/// background service for a place (it stops by itself when no place reminder is left).
Future<void> _schedule(int id, String summary, String? triggerType, DateTime? from) async {
  if (triggerType == 'time' && from != null) await scheduleNotification(id, summary, from);
  if (triggerType == 'location') await startWatch();
}

/// Background AI refinement: replaces the summary and optionally the category, list and emoji.
Future<void> updateReminderText(int id, {required String summary, String? category, String? list, String? emoji}) async {
  final ref = remindersCollection().doc('$id');
  sendWrite(ref.update({
    'summary': summary,
    'category': ?category,
    'list': ?list,
    'emoji': ?emoji,
  }));
  // The new summary is the event's title. The cache already has the update.
  if (calendarSyncNotifier.value) {
    unawaited(
      ref.get(const GetOptions(source: Source.cache)).then(
        (d) => syncReminderToCalendar('$id', d.data()),
        onError: (Object e) => debugPrint('Calendar sync: reminder $id not in cache: $e'),
      ),
    );
  }
}

/// Renames a list and moves its tasks along with it.
Future<void> renameList(String listId, String oldName, String newName) async {
  final batch = FirebaseFirestore.instance.batch();
  batch.update(listsCollection().doc(listId), {'name': newName});
  for (final d in (await remindersCollection().where('list', isEqualTo: oldName).get()).docs) {
    batch.update(d.reference, {'list': newName});
  }
  sendWrite(batch.commit());
}

/// Deletes a list; its tasks move to the Inbox.
Future<void> deleteList(String listId, String name) async {
  final batch = FirebaseFirestore.instance.batch();
  batch.delete(listsCollection().doc(listId));
  for (final d in (await remindersCollection().where('list', isEqualTo: name).get()).docs) {
    batch.update(d.reference, {'list': null});
  }
  sendWrite(batch.commit());
}
