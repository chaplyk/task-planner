import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/reminder.dart';
import '../reminder_extractor.dart';

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

  Future<void> _save(Reminder? reminder) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('reminders')
        .add(reminder?.toMap() ?? {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Reminder App'),
        actions: [
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
