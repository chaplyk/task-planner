import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:native_geofence/native_geofence.dart';

import 'app_check.dart';
import 'collections.dart';
import 'notifications.dart';
import 'store_detection.dart';

/// The one callback for every geofence, run by the plugin in a background isolate.
/// Stores (ids starting with [storeGeofencePrefix]) go to [storeGeofenceTriggered];
/// the rest are saved GPS places.
@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  debugPrint('Geofence ${params.event.name}: ${params.geofences.map((g) => g.id).join(', ')}');
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();
  if (FirebaseAuth.instance.currentUser == null) return;

  final storeIds = [
    for (final g in params.geofences)
      if (g.id.startsWith(storeGeofencePrefix)) g.id,
  ];
  if (storeIds.isNotEmpty) {
    await activateAppCheck();
    await initNotifications();
    await storeGeofenceTriggered(params.event, storeIds);
  }

  final placeIds = [
    for (final g in params.geofences)
      if (!g.id.startsWith(storeGeofencePrefix)) g.id,
  ];
  if (placeIds.isNotEmpty) await _savedPlaceTriggered(params.event, placeIds);
}

Future<void> _savedPlaceTriggered(GeofenceEvent geofenceEvent, List<String> ids) async {
  final String event;
  if (geofenceEvent == GeofenceEvent.enter) {
    event = 'enter';
  } else if (geofenceEvent == GeofenceEvent.exit) {
    event = 'exit';
  } else {
    return;
  }

  for (final id in ids) {
    final locationDoc = await locationsCollection().doc(id).get();
    final locationName = locationDoc.data()?['name'];

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
}
