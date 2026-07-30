import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:flutter/foundation.dart';
import 'notifications.dart';

ActivityType _activity = ActivityType.UNKNOWN;

Future<void> startActivityWatch() async {
  await initNotifications();

  FlutterActivityRecognition.instance.activityStream.listen((
    activity,
  ) {
    _activity = activity.type;
    _checkReminders(_activity.name);
  });
}

Future<void> _checkReminders(String activity) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final snapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('reminders')
      .where('status', isEqualTo: 'pending')
      .where('activity', isEqualTo: activity)
      .get();

  for (final doc in snapshot.docs) {
    await showNotification(int.parse(doc.id), doc.data()['summary'] ?? 'Reminder');
    await doc.reference.update({'status': 'done'});
  }
}