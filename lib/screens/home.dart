import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:siri_wave/siri_wave.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

import '../activity_watch.dart';
import '../collections.dart';
import '../models/reminder.dart';
import '../notifications.dart';
import '../gemma/extractor.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _methods = MethodChannel('speech/methods');
  static const _events = EventChannel('speech/events');
  static const _timeout = Duration(seconds: 15);

  final _extractor = ReminderExtractor();
  bool _recording = false;
  bool _thinking = false;
  Timer? _recordingTimer;

  FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  @override
  void initState() {
    super.initState();
    _events.receiveBroadcastStream().listen(_onEvent);
    _rescheduleAllNotifications();
    _watchActivity();
  }

  Future<void> _watchActivity() async {
    await Permission.activityRecognition.request();
    await startActivityWatch();
  }

  Future<void> _rescheduleAllNotifications() async {
    final snapshot = await remindersCollection().where('status', isEqualTo: 0).get();
    for (final doc in snapshot.docs) {
      final when = doc.data()['when'] as Timestamp?;
      if (when == null) continue;
      await scheduleNotification(
        int.parse(doc.id),
        doc.data()['summary'],
        when.toDate(),
      );
    }
  }

  Future<void> _signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Sign out failed: $e');
    }
  }

  Future<void> _toggle() async {
    if (_recording) {
      _recordingTimer?.cancel();
      await _methods.invokeMethod<void>('stop');
      setState(() => _recording = false);
      return;
    }

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      debugPrint('Microphone permission denied');
      return;
    }

    await _methods.invokeMethod<void>('start');
    setState(() => _recording = true);
    _recordingTimer = Timer(_timeout, _toggle);

    await FirebaseAnalytics.instance.logEvent(name: 'recording_started');
  }

  // Called by the bridge when it has recognized the speech
  Future<void> _onEvent(dynamic event) async {
    if (event['type'] != 'transcript') {
      debugPrint('Ignored speech event: $event');
      return;
    }

    setState(() => _thinking = true);
    try {
      final reminder = await _extractor.extract(event['text']);
      debugPrint('Reminder: $reminder');
      if ((reminder!.confidence ?? 0) < 0.7) {
        final confirmed = await _confirmReminder(reminder);
        if (confirmed != true) {
          setState(() => _thinking = false);
          return;
        }
      }
      await _save(reminder);
    } catch (e) {
      debugPrint('Extraction failed: $e');
    }
    setState(() => _thinking = false);
  }

  Future<bool?> _confirmReminder(Reminder reminder) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Not quite sure about this...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Summary: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: reminder.summary),
                  TextSpan(text: '\n'),
                  TextSpan(text: 'Condition: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: reminder.condition ?? ''),
                  TextSpan(text: '\n'),
                  TextSpan(text: 'Category: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: reminder.category),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Integer ID for Firestore - seconds since 2026
  Future<void> _save(Reminder? reminder) async {
    final id = DateTime.now().difference(DateTime.utc(2026)).inSeconds;
    await remindersCollection().doc('$id').set(reminder?.toMap() ?? {});
    if (reminder?.when != null && reminder!.triggerType == 'time') {
      await scheduleNotification(id, reminder.summary, reminder.when!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NagadAI'),
        actions: [
          if (FirebaseAuth.instance.currentUser?.isAnonymous == false)
            IconButton(onPressed: _signOut, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          _thinking
            ? const CircularProgressIndicator()
            : IconButton(
                onPressed: _toggle,
                iconSize: 96,
                icon: Icon(_recording ? Icons.stop : Icons.mic),
            ),
            SizedBox(height: 32),
            DefaultTextStyle(
              style: TextStyle(
                fontSize: 18.0,
                fontFamily: 'Agne',
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
              child: const Text('Just say: Remind me to...'),
            ),
            SizedBox(
              height: 80,
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 18.0,
                  fontFamily: 'Agne',
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: AnimatedTextKit(
                  repeatForever: true,
                  pause: const Duration(milliseconds: 1000),
                  animatedTexts: [
                    TypewriterAnimatedText(
                      'buy dog food next time I am driving',
                      speed: const Duration(milliseconds: 150),
                    ),
                    TypewriterAnimatedText(
                      'call mom tomorrow morning',
                      speed: const Duration(milliseconds: 150),
                    ),
                    TypewriterAnimatedText(
                      'pay bills when I get home',
                      speed: const Duration(milliseconds: 150),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 40),
            if (_recording) ...[
              SiriWaveform.ios7(
                controller: IOS7SiriWaveformController(
                  amplitude: 0.5,
                  color: Theme.of(context).colorScheme.primary,
                  frequency: 3,
                  speed: 0.09,
                ),
                options: const IOS7SiriWaveformOptions(height: 140, width: 400),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
