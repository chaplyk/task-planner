import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../collections.dart';
import '../settings/categories.dart';
import '../widgets/onboarding_demo.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  /// Gives a new account its starter category. A returning user already has
  /// categories, so signing in again must not add another "personal".
  Future<void> _seedCategories() async {
    if ((await categoriesCollection().limit(1).get()).docs.isNotEmpty) return;
    await categoriesCollection().add({'name': 'personal', 'emoji': '🧑', 'color': randomCategoryColor()});
  }

  Future<void> _signIn() async {
    try {
      final account = await GoogleSignIn.instance.authenticate();
      await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: account.authentication.idToken),
      );
      await _seedCategories();
      await FirebaseAnalytics.instance.logEvent(name: 'login', parameters: {'method': 'google'});
    } catch (e) {
      FirebaseCrashlytics.instance.recordError(e, StackTrace.current, reason: 'Google Sign In failed');
      debugPrint('Google Sign in failed: $e');
    }
  }

  Future<void> _continueAsGuest() async {
    try {
      await FirebaseAuth.instance.signInAnonymously();
      await _seedCategories();
      await FirebaseAnalytics.instance.logEvent(name: 'login', parameters: {'method': 'anonymous'});
    } catch (e) {
      FirebaseCrashlytics.instance.recordError(e, StackTrace.current, reason: 'Anonymous Sign In failed');
      debugPrint('Anonymous sign in failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          // Scrolls only on screens too short for everything; otherwise it fills the height.
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 32),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    Text('Say it once.\nForget about it.', style: theme.textTheme.headlineLarge),
                    const SizedBox(height: 10),
                    Text(
                      'Tell NagadAI what to remember. It reminds you at the right time, place or moment.',
                      style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    const OnboardingDemo(),
                    const Spacer(flex: 2),
                    SizedBox(
                      width: double.infinity,
                      child: Center(
                        child: GestureDetector(
                          onTap: _signIn,
                          child: Image.asset('assets/images/google_signin_button.png', height: 48),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(onPressed: _continueAsGuest, child: const Text('Continue as guest')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
