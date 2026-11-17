import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:native_geofence/native_geofence.dart';

import 'activity_watch.dart';
import 'calendar_sync.dart';
import 'collections.dart';
import 'store_detection.dart';

/// Removes everything this device does on behalf of the signed-in user: scheduled
/// notifications, place geofences, activity events and the background service. Without this they
/// keep firing the previous user's reminders after sign-out.
Future<void> clearDeviceState() async {
  Future<void> step(String name, Future<void> Function() run) async {
    try {
      await run();
    } catch (e) {
      debugPrint('Cleanup ($name) failed: $e');
    }
  }

  await step('notifications', AwesomeNotifications().cancelAll);
  await step('geofences', NativeGeofenceManager.instance.removeAllGeofences);
  await step('nearby stores', clearStoreState);
  await step('calendar', disableCalendarSync);
  await step('activity events', disableActivityReminders);
  await step('service', () async {
    if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
  });
}

Future<void> signOut() async {
  await clearDeviceState();
  await GoogleSignIn.instance.signOut();
  await FirebaseAuth.instance.signOut();
}

/// Deletes every document the user owns. The account itself holds no other data.
Future<void> _deleteUserData() async {
  final db = FirebaseFirestore.instance;
  for (final collection in [remindersCollection(), categoriesCollection(), locationsCollection(), listsCollection(), recurringCollection()]) {
    final docs = (await collection.get()).docs;
    // A batch takes at most 500 writes.
    for (var i = 0; i < docs.length; i += 400) {
      final batch = db.batch();
      for (final d in docs.skip(i).take(400)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }
}

/// Deletes the user's data, then the account. The data goes first, while the
/// user is still allowed to delete it.
///
/// Throws [FirebaseAuthException] if the account could not be deleted (for
/// example the user cancelled the Google prompt asking to confirm it is them).
Future<void> deleteAccount() async {
  final user = FirebaseAuth.instance.currentUser!;
  await _deleteUserData();
  await clearDeviceState();
  try {
    await user.delete();
  } on FirebaseAuthException catch (e) {
    if (e.code != 'requires-recent-login' || user.isAnonymous) rethrow;
    // Firebase only deletes an account shortly after a sign-in: confirm with Google and retry.
    final account = await GoogleSignIn.instance.authenticate();
    await user.reauthenticateWithCredential(
      GoogleAuthProvider.credential(idToken: account.authentication.idToken),
    );
    await user.delete();
  }
  await GoogleSignIn.instance.signOut();
}
