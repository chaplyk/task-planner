import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
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
  // Notification permission is asked after the first reminder, not at launch.
  await NativeGeofenceManager.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
    );
  }
}

const _brandCoral = Color(0xFFFE6D73);

ThemeData _theme(Brightness brightness) {
  // Fidelity keeps the primary close to the actual brand coral instead of a muted tone.
  final scheme = ColorScheme.fromSeed(
    seedColor: _brandCoral,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = base.textTheme;
  return base.copyWith(
    textTheme: text.copyWith(
      headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    chipTheme: base.chipTheme.copyWith(shape: const StadiumBorder()),
  );
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
