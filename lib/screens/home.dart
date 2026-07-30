import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:permission_handler/permission_handler.dart';

import '../activity_watch.dart';
import '../collections.dart';
import '../models/reminder.dart';
import '../notifications.dart';
import '../reminder_extractor.dart';
import '../screens/reminders.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _methods = MethodChannel('speech/methods');
  static const _events = EventChannel('speech/events');

  final _extractor = ReminderExtractor();
  bool _recording = false;
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    _events.receiveBroadcastStream().listen(_onEvent);
    _rescheduleAllNotifications();
    _watchActivity();
  }

  Future<void> _watchActivity() async {
    final status = await Permission.activityRecognition.request();
    print('Activity permission: $status');
    if (!status.isGranted) {
      print('Activity watch not started (permission denied)');
      return;
    }
    await startActivityWatch();
  }

  Future<void> _rescheduleAllNotifications() async {
    final snapshot = await reminders().where('status', isEqualTo: 0).get();
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
      await _save(reminder);
    } catch (e) {
      debugPrint('Extraction failed: $e');
    }
    setState(() => _thinking = false);
  }

  // Integer ID for Firestore - seconds since 2026
  Future<void> _save(Reminder? reminder) async {
    final id = DateTime.now().difference(DateTime.utc(2026)).inSeconds;
    await reminders().doc('$id').set(reminder?.toMap() ?? {});
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
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RemindersScreen()),
              );
            },
            icon: const Icon(Icons.checklist),
          ),
          IconButton(onPressed: _signOut, icon: const Icon(Icons.logout)),
        ],
      ),
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
