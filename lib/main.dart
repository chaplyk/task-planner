import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:native_geofence/native_geofence.dart';

import 'activity_watch.dart';
import 'llm/model_choice.dart';
import 'notifications.dart';
import 'screens/onboarding.dart';
import 'screens/startup.dart';

// Fixed App Check debug token registered in Firebase Console, so debug builds keep
// working across reinstalls. Pass with --dart-define=APP_CHECK_DEBUG_TOKEN=<uuid>.
// When empty, the SDK generates a random token per install.
const _appCheckDebugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  await GoogleSignIn.instance.initialize();
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kDebugMode
        ? AndroidDebugProvider(
            debugToken: _appCheckDebugToken.isEmpty ? null : _appCheckDebugToken,
          )
        : const AndroidPlayIntegrityProvider(),
  );
  await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
  await loadModelChoice();
  await loadPollPeriod();
  await initNotifications();
  await askNotificationPermission();
  await NativeGeofenceManager.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(colorSchemeSeed: const Color.fromARGB(255, 53, 135, 203)),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.data == null) return const OnboardingScreen();
        return const StartupScreen();
      },
    );
  }
}
