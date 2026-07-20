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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    await Permission.microphone.request();

    _subscription = _events.receiveBroadcastStream().listen(
      (dynamic text) => debugPrint('Recognized: $text'),
      onError: (Object e) => debugPrint('Recognition error: $e'),
    );

    await _methods.invokeMethod<void>('start');
  }

  @override
  void dispose() {
    _methods.invokeMethod<void>('stop');
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Icon(Icons.mic, size: 64)));
  }
}
