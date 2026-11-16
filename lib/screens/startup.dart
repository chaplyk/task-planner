import 'package:material_ui/material_ui.dart';

import '../gemma/download.dart';
import '../llm/model_choice.dart';
import 'root.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    // Location permission is requested when the user adds a place, not at launch.
    // Resume an interrupted local model download in the background.
    if (modelChoiceNotifier.value == LlmModel.local) {
      ensureLocalModel().catchError((e) => debugPrint('Model download failed: $e'));
    }
  }

  @override
  Widget build(BuildContext context) => const RootScreen();
}
