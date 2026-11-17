import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

// Fixed App Check debug token registered in Firebase Console, so debug builds keep
// working across reinstalls. Pass with --dart-define=APP_CHECK_DEBUG_TOKEN=<uuid>.
// When empty, the SDK generates a random token per install.
const _appCheckDebugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');

/// Must run in every process start that talks to Firebase, including background
/// entrypoints that run without the app being opened.
Future<void> activateAppCheck() => FirebaseAppCheck.instance.activate(
  providerAndroid: kDebugMode
      ? AndroidDebugProvider(debugToken: _appCheckDebugToken.isEmpty ? null : _appCheckDebugToken)
      : const AndroidPlayIntegrityProvider(),
);
