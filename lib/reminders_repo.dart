import 'package:cloud_firestore/cloud_firestore.dart';

import 'collections.dart';
import 'models/reminder.dart';
import 'notifications.dart';

typedef ReminderDoc = DocumentSnapshot<Map<String, dynamic>>;

// Writes here go through [sendWrite]: the notification work that follows must not wait
// for the server, or it would never happen while offline.

/// Saves a new reminder and schedules its notification. Returns the reminder id
/// (seconds since 2026, also used as the notification id).
Future<int> saveReminder(Reminder reminder) async {
  final id = DateTime.now().difference(DateTime.utc(2026)).inSeconds;
  sendWrite(remindersCollection().doc('$id').set(reminder.toMap()));
  await _schedule(id, reminder.summary, reminder.triggerType, reminder.when);
  return id;
}

/// Whether the user has never created a reminder.
Future<bool> isFirstReminder() async =>
    (await remindersCollection().limit(1).get()).docs.isEmpty;

Reminder reminderFromDoc(ReminderDoc doc) {
  final data = doc.data() ?? const {};
  return Reminder(
    summary: data['summary'] ?? '',
    when: (data['when'] as Timestamp?)?.toDate(),
    condition: data['condition'],
    transcript: data['transcript'],
    triggerType: data['triggerType'] ?? 'none',
    activity: data['activity'],
    location: data['location'],
    locationEvent: data['locationEvent'],
    category: data['category'],
    list: data['list'],
    confidence: (data['confidence'] as num?)?.toDouble(),
  );
}

/// Replaces the editable fields of an existing reminder and reschedules it.
Future<void> updateReminder(ReminderDoc doc, Reminder updated) async {
  sendWrite(doc.reference.update({
    'summary': updated.summary,
    'when': updated.when == null ? null : Timestamp.fromDate(updated.when!),
    'condition': updated.condition,
    'triggerType': updated.triggerType,
    'activity': updated.activity,
    'location': updated.location,
    'locationEvent': updated.locationEvent,
    'category': updated.category,
    'list': updated.list,
    'notified': false,
  }));
  final id = int.parse(doc.id);
  await cancelNotification(id);
  await _schedule(id, updated.summary, updated.triggerType, updated.when);
}

Future<void> completeReminder(ReminderDoc doc) async {
  sendWrite(doc.reference.update({'status': 1, 'completedAt': Timestamp.now()}));
  await cancelNotification(int.parse(doc.id));
}

Future<void> reopenReminder(ReminderDoc doc) async {
  sendWrite(doc.reference.update({'status': 0, 'completedAt': null, 'notified': false}));
  final r = reminderFromDoc(doc);
  await _schedule(int.parse(doc.id), r.summary, r.triggerType, r.when);
}

/// Clears the "notified" flag so an activity or place reminder can fire again.
void clearNotified(ReminderDoc doc) => sendWrite(doc.reference.update({'notified': false}));

/// Deletes a reminder. Returns its data so it can be restored with [restoreReminder].
Future<Map<String, dynamic>?> deleteReminder(ReminderDoc doc) async {
  final data = doc.data();
  sendWrite(doc.reference.delete());
  await cancelNotification(int.parse(doc.id));
  return data;
}

Future<void> deleteReminderById(int id) async {
  sendWrite(remindersCollection().doc('$id').delete());
  await cancelNotification(id);
}

Future<void> restoreReminder(String id, Map<String, dynamic> data) async {
  sendWrite(remindersCollection().doc(id).set(data));
  final when = (data['when'] as Timestamp?)?.toDate();
  await _schedule(int.parse(id), data['summary'] ?? '', data['triggerType'], when);
}

Future<void> _schedule(int id, String summary, String? triggerType, DateTime? when) async {
  if (triggerType == 'time' && when != null) await scheduleNotification(id, summary, when);
}

/// Background AI refinement: replaces the summary and optionally the category and list.
Future<void> updateReminderText(int id, {required String summary, String? category, String? list}) async {
  sendWrite(remindersCollection().doc('$id').update({
    'summary': summary,
    'category': ?category,
    'list': ?list,
  }));
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
