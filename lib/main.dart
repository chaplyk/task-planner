import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:native_geofence/native_geofence.dart';

import 'app_check.dart';
import 'llm/model_choice.dart';
import 'theme_choice.dart';
import 'notifications.dart';
import 'screens/onboarding.dart';
import 'screens/startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Nothing works without Firebase (sign-in, data), so this one is fatal.
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase failed to start: $e');
    runApp(const _StartupFailedApp());
    return;
  }
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  // Errors outside the widget tree (async code, platform channels) would otherwise go unreported.
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // The rest each power one feature. A failure is reported and the app still opens.
  await _init('Google Sign-In', () => GoogleSignIn.instance.initialize());
  await _init('App Check', activateAppCheck);
  await _init('Gemma', () => FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]));
  await _init('model choice', loadModelChoice);
  await _init('theme', loadThemeMode);
  await _init('notifications', initNotifications);
  // Notification permission is asked after the first reminder, not at launch.
  await _init('geofences', () => NativeGeofenceManager.instance.initialize());
  runApp(const MyApp());
}

Future<void> _init(String name, Future<void> Function() run) async {
  try {
    await run();
  } catch (e, stack) {
    debugPrint('Startup: $name failed: $e');
    FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Startup: $name failed');
  }
}

/// Shown instead of a blank screen when the app cannot start at all.
class _StartupFailedApp extends StatelessWidget {
  const _StartupFailedApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('😕', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 16),
                const Text('NagadAI couldn’t start', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Something went wrong while starting up.', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                const FilledButton(onPressed: main, child: Text('Try again')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: mode,
        home: const SplashScreen(),
      ),
    );
  }
}

const _brandBlue = Color(0xFFA2D2FF);

ThemeData _theme(Brightness brightness) {
  // Fidelity keeps the brand light blue itself as the container colour (chips, highlights,
  // tile circles), with a deeper blue of the same hue as primary so text on it stays readable.
  final scheme = ColorScheme.fromSeed(
    seedColor: _brandBlue,
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
