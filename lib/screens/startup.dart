import 'package:flutter/material.dart';

import '../gemma/download.dart';
import '../permissions.dart';
import '../widgets/typewriter.dart';
import 'root.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  int _percent = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _download();
    requestBackgroundLocationPermission(context);
  }

  Future<void> _download() async {
    try {
      await downloadModel(
        onProgress: (percent) {
          setState(() => _percent = percent);
        },
      );
      setState(() => _ready = true);
    } catch (e) {
      debugPrint('Model download failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const RootScreen();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Downloading model... $_percent%'),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _percent / 100),
            const SizedBox(height: 32),
            const Typewriter(),
          ],
        ),
      ),
    );
  }
}
