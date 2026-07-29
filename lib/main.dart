import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:permission_handler/permission_handler.dart';

import 'model_download.dart';
import 'onboarding_screen.dart';
import 'reminder_extractor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await GoogleSignIn.instance.initialize();
  await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: SplashScreen());
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

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  int _percent = 0;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    try {
      await downloadModel(
        onProgress: (percent) {
          if (mounted) setState(() => _percent = percent);
        },
      );
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('Model download failed: $e');
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const SpeechScreen();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _error != null
              ? [Text('Download failed:\n$_error', textAlign: TextAlign.center)]
              : [
                  Text('Downloading model... $_percent%'),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _percent / 100),
                ],
        ),
      ),
    );
  }
}

class SpeechScreen extends StatefulWidget {
  const SpeechScreen({super.key});

  @override
  State<SpeechScreen> createState() => _SpeechScreenState();
}

class _SpeechScreenState extends State<SpeechScreen> {
  static const _methods = MethodChannel('speech/methods');
  static const _events = EventChannel('speech/events');

  final _extractor = ReminderExtractor();
  StreamSubscription<dynamic>? _subscription;
  bool _recording = false;
  bool _thinking = false;

  @override
  void dispose() {
    _subscription?.cancel();
    _extractor.close();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_recording) {
      await _methods.invokeMethod<void>('stop');
      setState(() => _recording = false);
      return;
    }

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      debugPrint('Microphone permission denied');
      return;
    }

    _subscription ??= _events.receiveBroadcastStream().listen(_onEvent);
    await _methods.invokeMethod<void>('start');
    setState(() => _recording = true);
  }

  Future<void> _onEvent(dynamic event) async {
    final type = event['type'];
    final text = event['text'];
    if (type == 'error') {
      debugPrint('Recognition error: $text');
      return;
    }
    if (type != 'transcript') return;

    debugPrint('Recognized: $text');
    setState(() => _thinking = true);
    try {
      final reminder = await _extractor.extract(text as String);
      debugPrint('Reminder JSON: ${reminder == null ? 'none' : jsonEncode(reminder)}');
    } catch (e) {
      debugPrint('Extraction failed: $e');
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _thinking
            ? const CircularProgressIndicator()
            : IconButton(
                onPressed: _toggle,
                iconSize: 96,
                icon: Icon(_recording ? Icons.stop : Icons.mic),
              ),
      ),
    );
  }
}
