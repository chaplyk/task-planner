import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'notifications.dart';

// Interval between activity checks
const interval = 120 * 1000;

// The callback function should always be a top-level or static function.
@pragma('vm:entry-point')
void startActivityWatchCallback() {
  FlutterForegroundTask.setTaskHandler(_ActivityTaskHandler());
}

class _ActivityTaskHandler extends TaskHandler {
  ActivityType _activity = ActivityType.UNKNOWN;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await Firebase.initializeApp();
    await initNotifications();

    FlutterActivityRecognition.instance.activityStream.listen((
      activity,
    ) {
      _activity = activity.type;
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    debugPrint('Current activity: ${_activity.name}');
    _checkReminders(_activity.name);
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

Future<void> _checkReminders(String activity) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final snapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('reminders')
      .where('status', isEqualTo: 0)
      .where('activity', isEqualTo: activity)
      .where('notified', isEqualTo: false)
      .get();

  for (final doc in snapshot.docs) {
    await showNotification(int.parse(doc.id), doc.data()['summary'] ?? 'Reminder');
    await doc.reference.update({'notified': true});
  }
}

Future<void> startActivityWatch() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'activity_watch',
      channelName: 'Activity Watch',
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(interval),
      autoRunOnBoot: true,
    ),
  );

  await FlutterForegroundTask.startService(
    notificationTitle: 'Watching for Activities',
    notificationText: '',
    callback: startActivityWatchCallback,
  );
}
