import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Sends a Firestore write without waiting for the server.
///
/// Firestore applies a write to its local cache at once (listeners see it immediately)
/// and syncs it when online, but the write's future only completes when the server
/// answers. Offline that never happens, so awaiting it would hang whatever comes next:
/// scheduling a notification, showing an Undo, moving to the next reminder.
void sendWrite(Future<void> write) {
  unawaited(write.catchError((Object e) => debugPrint('Firestore write failed: $e')));
}

DocumentReference<Map<String, dynamic>> userDoc() {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  return FirebaseFirestore.instance.collection('users').doc(uid);
}

CollectionReference<Map<String, dynamic>> remindersCollection() {
  return userDoc().collection('reminders');
}

CollectionReference<Map<String, dynamic>> categoriesCollection() {
  return userDoc().collection('categories');
}

CollectionReference<Map<String, dynamic>> locationsCollection() {
  return userDoc().collection('locations');
}

CollectionReference<Map<String, dynamic>> listsCollection() {
  return userDoc().collection('lists');
}

CollectionReference<Map<String, dynamic>> recurringCollection() {
  return userDoc().collection('recurring');
}
