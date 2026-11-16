import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notifications.dart';
import 'collections.dart';
import 'store_detection.dart';

const _pollPeriodKey = 'poll_period_seconds';

// Selectable intervals between activity checks
const pollPeriods = [
  Duration(seconds: 30),
  Duration(seconds: 45),
  Duration(minutes: 1),
  Duration(minutes: 2),
  Duration(minutes: 5),
  Duration(minutes: 10),
];

final pollPeriodNotifier = ValueNotifier<Duration>(const Duration(seconds: 45));

Future<void> loadPollPeriod() async {
  final prefs = await SharedPreferences.getInstance();
  final seconds = prefs.getInt(_pollPeriodKey);
  if (seconds != null) pollPeriodNotifier.value = Duration(seconds: seconds);
}

Future<void> setPollPeriod(Duration period) async {
  pollPeriodNotifier.value = period;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_pollPeriodKey, period.inSeconds);
  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.updateService(foregroundTaskOptions: _taskOptions());
  }
}

String formatPollPeriod(Duration d) =>
    d.inSeconds < 60 ? '${d.inSeconds} s' : '${d.inMinutes} min';

ForegroundTaskOptions _taskOptions() => ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(pollPeriodNotifier.value.inMilliseconds),
      autoRunOnBoot: true,
    );

// The callback function should always be a top-level or static function.
@pragma('vm:entry-point')
void startWatchCallback() {
  FlutterForegroundTask.setTaskHandler(_ActivityTaskHandler());
}

class _ActivityTaskHandler extends TaskHandler {
  ActivityType _activity = ActivityType.UNKNOWN;
  final _stores = StoreReminderWatcher();
  String? _lastWifiName;

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
  Future<void> onRepeatEvent(DateTime timestamp) async {
    if (FirebaseAuth.instance.currentUser == null) return;

    debugPrint('Current activity: ${_activity.name}');
    _checkActivityReminders(_activity.name);
    _stores.tick(timestamp).catchError((Object e) => debugPrint('Store check failed: $e'));

    final wifiName = await NetworkInfo().getWifiName();
    if (wifiName == _lastWifiName) return;
    if (_lastWifiName != null) _checkWifiReminders(_lastWifiName, 'exit');
    _lastWifiName = wifiName;
    if (wifiName != null) _checkWifiReminders(wifiName, 'enter');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

Future<void> _checkActivityReminders(String activity) async {
  final snapshot = await remindersCollection()
      .where('status', isEqualTo: 0)
      .where('activity', isEqualTo: activity)
      .where('notified', isEqualTo: false)
      .get();

  for (final doc in snapshot.docs) {
    await showNotification(int.parse(doc.id), doc.data()['summary'] ?? 'Reminder');
    await doc.reference.update({'notified': true});
  }
}

Future<void> _checkWifiReminders(String? wifiName, String event) async {
  final wifiLocationDoc = await locationsCollection().where('wifi', isEqualTo: wifiName).limit(1).get();
  if (wifiLocationDoc.docs.isEmpty) return;
  final locationName = wifiLocationDoc.docs.first.data()['name'];

  final snapshot = await remindersCollection()
      .where('status', isEqualTo: 0)
      .where('location', isEqualTo: locationName)
      .where('locationEvent', isEqualTo: event)
      .where('notified', isEqualTo: false)
      .get();

  for (final doc in snapshot.docs) {
    await showNotification(int.parse(doc.id), doc.data()['summary'] ?? 'Reminder');
    await doc.reference.update({'notified': true});
  }
}

Future<void> startWatch() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'reminders_watch',
      channelName: 'Reminders Watch',
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: _taskOptions(),
  );

  await FlutterForegroundTask.startService(
    notificationTitle: 'NagadAI is running in background',
    notificationText: '',
    callback: startWatchCallback,
  );
}
