import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../collections.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _page = 0;

  Future<void> _signIn() async {
    try {
      final account = await GoogleSignIn.instance.authenticate();
      await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: account.authentication.idToken),
      );
      await categoriesCollection().add({'name': 'personal'}); // add safeguard later
    } catch (e) {
      debugPrint('Sign in failed: $e');
    }
  }

  Future<void> _continueAsGuest() async {
    try {
      await FirebaseAuth.instance.signInAnonymously();
      await categoriesCollection().add({'name': 'personal'}); // add safeguard later
    } catch (e) {
      debugPrint('Anonymous sign in failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: PageView(
              onPageChanged: (i) => setState(() => _page = i),
              children: const [
                _Page(
                  icon: Icons.mic,
                  title: 'Tap to speak',
                  text: 'Record your thoughts and ideas.',
                ),
                _Page(
                  icon: Icons.auto_awesome,
                  title: 'Use AI',
                  text: 'AI Model will process your prompt.',
                ),
                _Page(
                  icon: Icons.notifications_active,
                  title: 'Get SMART reminders!',
                  text: 'App will notify you when it matters!',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: _page == 2
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: _signIn,
                        child: Image.asset(
                          'assets/images/google_signin_button.png',
                          height: 48,
                        ),
                      ),
                      TextButton(
                        onPressed: _continueAsGuest,
                        child: const Text('Continue as guest'),
                      ),
                    ],
                  )
                : const Text('Swipe to continue'),
          ),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 96),
          const SizedBox(height: 32),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
