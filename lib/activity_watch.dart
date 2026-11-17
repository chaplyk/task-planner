import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_check.dart';
import 'notifications.dart';
import 'collections.dart';
import 'store_detection.dart';

const _pollPeriodKey = 'poll_period_seconds';

// Selectable intervals between Wi-Fi and store checks
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

// ---------------------------------------------------------------- activity reminders
//
// "Next time I drive" reminders don't use the background service. Android (Google Play
// services) tells the app when the user starts driving, cycling, running or walking, even
// when the app is closed: see ActivityTransitions.kt and ActivityTransitionWorker.kt.

const _activityMethods = MethodChannel('activity/methods');
const _transitionChannel = MethodChannel('activity/transition');

/// Turns activity reminders on for this device. Needs the activity recognition permission.
Future<void> enableActivityReminders() async {
  try {
    await _activityMethods.invokeMethod<void>('register');
  } catch (e) {
    debugPrint('Activity reminders could not be turned on: $e');
  }
}

Future<void> disableActivityReminders() async {
  try {
    await _activityMethods.invokeMethod<void>('unregister');
  } catch (e) {
    debugPrint('Activity reminders could not be turned off: $e');
  }
}

/// Started by ActivityTransitionWorker in a headless engine when the user begins an
/// activity. Tells the worker it is ready, then shows the reminders for the activity
/// the worker sends ('IN_VEHICLE', ...). An error here reaches the worker as a failure.
@pragma('vm:entry-point')
void activityTransitionMain() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  _transitionChannel.setMethodCallHandler((call) async {
    if (call.method != 'transition') return;
    final activity = (call.arguments as Map)['activity'] as String;
    await Firebase.initializeApp();
    if (FirebaseAuth.instance.currentUser == null) return;
    await activateAppCheck();
    await initNotifications();
    await _checkActivityReminders(activity);
  });
  _transitionChannel.invokeMethod<void>('ready');
}

// ---------------------------------------------------------------- background service
//
// Polls for Wi-Fi place and store reminders.

// The callback function should always be a top-level or static function.
@pragma('vm:entry-point')
void startWatchCallback() {
  FlutterForegroundTask.setTaskHandler(_ActivityTaskHandler());
}

class _ActivityTaskHandler extends TaskHandler {
  final _stores = StoreReminderWatcher();
  String? _lastWifiName;
  bool _wifiKnown = false;
  int _missedWifiReads = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await Firebase.initializeApp();
    await initNotifications();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    if (FirebaseAuth.instance.currentUser == null) return;

    _stores.tick(timestamp).catchError((Object e) => debugPrint('Store check failed: $e'));
    try {
      await _checkWifi();
    } catch (e) {
      debugPrint('Wi-Fi check failed: $e');
    }
  }

  /// Fires Wi-Fi place reminders when the network really changed. A missing name
  /// is only trusted as "left" when Android would have told us the name.
  Future<void> _checkWifi() async {
    // Android hides the network name without location access, and in the background
    // without "Allow all the time". A null name then means "unknown", not "disconnected".
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) return;
    if (!await Geolocator.isLocationServiceEnabled()) return;

    final wifiName = await NetworkInfo().getWifiName();
    if (wifiName == null && permission != LocationPermission.always) return;

    if (!_wifiKnown) {
      // First reading after the service (re)starts: where the user already is, not an arrival.
      _wifiKnown = true;
      _lastWifiName = wifiName;
      return;
    }
    if (wifiName == _lastWifiName) {
      _missedWifiReads = 0;
      return;
    }
    // A brief drop is not leaving: the network must stay gone for a second poll.
    if (wifiName == null && ++_missedWifiReads < 2) return;
    _missedWifiReads = 0;

    final previous = _lastWifiName;
    _lastWifiName = wifiName;
    if (previous != null) await _checkWifiReminders(previous, 'exit');
    if (wifiName != null) await _checkWifiReminders(wifiName, 'enter');
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
