import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: SpeechScreen());
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

  StreamSubscription<dynamic>? _subscription;
  bool _recording = false;

  @override
  void dispose() {
    _subscription?.cancel();
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

  void _onEvent(dynamic event) {
    final type = event['type'];
    final text = event['text'];
    if (type == 'transcript') {
      debugPrint('Recognized: $text');
    } else if (type == 'error') {
      debugPrint('Recognition error: $text');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: IconButton(
          onPressed: _toggle,
          iconSize: 96,
          icon: Icon(_recording ? Icons.stop : Icons.mic),
        ),
      ),
    );
  }
}
