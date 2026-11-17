import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'app_check.dart';
import 'notifications.dart';
import 'collections.dart';
import 'place_types.dart';
import 'store_detection.dart';
import 'store_log.dart';

/// How often the stores near the user are looked up again and their geofences renewed
/// (they expire after [storeGeofenceExpiration]). Visits themselves are noticed by the
/// geofences, not by polling. Wi-Fi places follow network change events.
const _storeCheckPeriod = Duration(minutes: 15);

/// A Wi-Fi drop must last this long to count as leaving (routers and phones blip).
const _wifiLossGrace = Duration(seconds: 30);

ForegroundTaskOptions _taskOptions() => ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(_storeCheckPeriod.inMilliseconds),
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
// Runs only while a place reminder is waiting. Wi-Fi places react to network change
// events; store reminders refresh the nearby stores' geofences every [_storeCheckPeriod].

// The callback function should always be a top-level or static function.
@pragma('vm:entry-point')
void startWatchCallback() {
  FlutterForegroundTask.setTaskHandler(_ActivityTaskHandler());
}

class _ActivityTaskHandler extends TaskHandler {
  final _stores = StoreGeofencer();
  // Store kinds the waiting reminders ask for, as of the last refresh.
  Set<String>? _storeKinds;

  // The place reminders still waiting to fire, kept current by one Firestore listener.
  // Asking the server on every poll instead costs a billed read each time, even when
  // nothing changed: thousands a day per user.
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _waitingSub;
  StreamSubscription<List<ConnectivityResult>>? _networkSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _waiting; // null until first loaded
  String? _lastWifiName;
  bool _wifiKnown = false;
  // Pending check that a Wi-Fi drop lasted long enough to count as leaving.
  Timer? _lossTimer;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await Firebase.initializeApp();
    await initNotifications();
    try {
      await NativeGeofenceManager.instance.initialize();
    } catch (e) {
      await storeLog('Service: geofences unavailable ($e)');
    }
    await storeLog('Service started (${starter.name})');
    // Follow sign-in and sign-out: the reminders belong to the current user.
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_watchReminders);
    // Android calls back on every network change, so Wi-Fi needs no polling.
    _networkSub = Connectivity().onConnectivityChanged.listen((_) => _onNetworkChanged());
  }

  void _watchReminders(User? user) {
    _waitingSub?.cancel();
    _waitingSub = null;
    _waiting = null;
    if (user == null) return;
    _waitingSub = waitingPlaceReminders().snapshots().listen(
      (s) {
        _waiting = s.docs;
        // A store kind added or gone (or the first load): refresh now rather than at
        // the next repeat event, up to [_storeCheckPeriod] away.
        if (!setEquals(_storeKindsOf(s.docs), _storeKinds)) _refreshStores();
        if (!_hasWifiPlaces) {
          _wifiKnown = false; // take a fresh baseline when such a reminder appears
          _lossTimer?.cancel();
        } else if (!_wifiKnown) {
          _readWifi();
        }
        // Nothing left to watch: stop, and take the ongoing notification with it.
        // Only the server's answer counts; an empty cache right after start is not "none".
        if (s.docs.isEmpty && !s.metadata.isFromCache) FlutterForegroundTask.stopService();
      },
      onError: (Object e) => debugPrint('Watching place reminders failed: $e'),
    );
  }

  static Set<String> _storeKindsOf(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) => {
    for (final d in docs)
      if (isStoreArrival(d.data())) d.data()['location'] as String,
  };

  /// Whether a saved-place (Wi-Fi) reminder is waiting, as opposed to only store reminders.
  bool get _hasWifiPlaces => (_waiting ?? const []).any((d) => !isStoreType(d.data()['location'] as String?));

  @override
  Future<void> onRepeatEvent(DateTime timestamp) => _refreshStores();

  Future<void> _refreshStores() async {
    final waiting = _waiting;
    if (FirebaseAuth.instance.currentUser == null || waiting == null) return;
    final kinds = _storeKindsOf(waiting);
    if (!setEquals(kinds, _storeKinds)) {
      await storeLog('Service: store reminders waiting for ${kinds.isEmpty ? 'nothing' : kinds.join(', ')}');
    }
    _storeKinds = kinds;
    await _stores.refresh(waiting).catchError((Object e) => debugPrint('Store refresh failed: $e'));
  }

  Future<void> _onNetworkChanged() async {
    if (FirebaseAuth.instance.currentUser == null || !_hasWifiPlaces) return;
    // Right after connecting, Android often can't name the network yet.
    await Future<void>.delayed(const Duration(seconds: 2));
    await _readWifi();
  }

  /// Reads the current network name and acts on it. [confirmingLoss] is the re-check
  /// [_wifiLossGrace] after the Wi-Fi dropped.
  Future<void> _readWifi({int attempt = 0, bool confirmingLoss = false}) async {
    try {
      // Android hides the network name without location access, and in the background
      // without "Allow all the time". A null name then means "unknown", not "disconnected".
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) return;
      if (!await Geolocator.isLocationServiceEnabled()) return;

      final wifiName = await NetworkInfo().getWifiName();
      if (wifiName == null && permission != LocationPermission.always) return;
      if (wifiName == null && (await Connectivity().checkConnectivity()).contains(ConnectivityResult.wifi)) {
        // Connected but not named yet: try again shortly rather than treat it as gone.
        if (attempt < 3) {
          Future<void>.delayed(const Duration(seconds: 3), () => _readWifi(attempt: attempt + 1));
        }
        return;
      }
      await _apply(wifiName, confirmed: confirmingLoss);
    } catch (e) {
      debugPrint('Wi-Fi check failed: $e');
    }
  }

  /// Fires Wi-Fi place reminders when the network really changed.
  Future<void> _apply(String? wifiName, {required bool confirmed}) async {
    if (!_wifiKnown) {
      // First reading after the service (re)starts: where the user already is, not an arrival.
      _wifiKnown = true;
      _lastWifiName = wifiName;
      return;
    }
    if (wifiName == _lastWifiName) {
      _lossTimer?.cancel(); // back on the same network before the grace ran out
      return;
    }
    if (wifiName == null && !confirmed) {
      // A brief drop is not leaving: check again once the grace period has passed.
      _lossTimer?.cancel();
      _lossTimer = Timer(_wifiLossGrace, () => _readWifi(confirmingLoss: true));
      return;
    }
    _lossTimer?.cancel();

    final previous = _lastWifiName;
    _lastWifiName = wifiName;
    final waiting = _waiting ?? const [];
    if (previous != null) await _checkWifiReminders(previous, 'exit', waiting);
    if (wifiName != null) await _checkWifiReminders(wifiName, 'enter', waiting);
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await storeLog('Service stopped${isTimeout ? ' (timeout)' : ''}');
    _lossTimer?.cancel();
    await _networkSub?.cancel();
    await _waitingSub?.cancel();
    await _authSub?.cancel();
  }
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

/// Fires the [waiting] reminders tied to the saved place whose Wi-Fi network is [wifiName].
Future<void> _checkWifiReminders(
  String wifiName,
  String event,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> waiting,
) async {
  final wifiLocationDoc = await locationsCollection().where('wifi', isEqualTo: wifiName).limit(1).get();
  if (wifiLocationDoc.docs.isEmpty) return;
  final locationName = wifiLocationDoc.docs.first.data()['name'];

  for (final doc in waiting) {
    if (doc.data()['location'] != locationName || doc.data()['locationEvent'] != event) continue;
    await showNotification(int.parse(doc.id), doc.data()['summary'] ?? 'Reminder');
    sendWrite(doc.reference.update({'notified': true}));
  }
}

/// Starts the background service if it isn't running. It stops by itself once no place
/// reminder is waiting, so call this whenever one is created, reopened or re-armed.
Future<void> startWatch() async {
  if (await FlutterForegroundTask.isRunningService) return;
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
