import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../collections.dart';
import '../settings/categories.dart';
import '../widgets/onboarding_tour.dart';

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

  /// While a sign-in is under way: the buttons wait instead of starting another.
  bool _busy = false;

  Future<void> _run(Future<void> Function() signIn) async {
    if (_busy) return;
    setState(() => _busy = true);
    await signIn();
    // On success this screen is already being replaced.
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return OnboardingTour(
      onPage: (page) => FirebaseAnalytics.instance.logEvent(name: 'onboarding_page', parameters: {'index': page}),
      onSkip: (page) => FirebaseAnalytics.instance.logEvent(name: 'onboarding_skip', parameters: {'from': page}),
      signInActions: AnimatedOpacity(
        opacity: _busy ? 0.5 : 1,
        duration: const Duration(milliseconds: 200),
        child: Column(
          children: [
            Center(
              child: Semantics(
                button: true,
                label: 'Sign in with Google',
                excludeSemantics: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => _run(_signIn),
                    customBorder: const StadiumBorder(),
                    child: Ink.image(
                      image: const AssetImage('assets/images/google_signin_button.png'),
                      width: 52 * 354 / 80,
                      height: 52,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(onPressed: () => _run(_continueAsGuest), child: const Text('Continue as guest')),
            Text(
              'As a guest, your reminders stay on this phone only.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
