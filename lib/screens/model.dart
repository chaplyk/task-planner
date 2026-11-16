import 'package:flutter/material.dart';

import '../gemma/download.dart';
import '../llm/model_choice.dart';

String modelLabel(LlmModel model) => switch (model) {
      LlmModel.gemini => 'Gemini (cloud)',
      LlmModel.local => 'On-device (Gemma)',
    };

class ModelScreen extends StatefulWidget {
  const ModelScreen({super.key});

  @override
  State<ModelScreen> createState() => _ModelScreenState();
}

class _ModelScreenState extends State<ModelScreen> {
  Future<void> _selectModel(LlmModel? model) async {
    if (model == null || model == modelChoiceNotifier.value) return;
    await setModelChoice(model);
    if (model != LlmModel.local) return;
    try {
      await ensureLocalModel();
    } catch (e) {
      debugPrint('Model download failed: $e');
      await setModelChoice(LlmModel.gemini);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model download failed. Using Gemini.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Model')),
      body: ValueListenableBuilder<LlmModel>(
        valueListenable: modelChoiceNotifier,
        builder: (context, model, _) => RadioGroup<LlmModel>(
          groupValue: model,
          onChanged: _selectModel,
          child: ListView(
            children: [
              RadioListTile<LlmModel>(
                title: Text(modelLabel(LlmModel.gemini)),
                subtitle: const Text('Fast, requires internet'),
                value: LlmModel.gemini,
              ),
              RadioListTile<LlmModel>(
                title: Text(modelLabel(LlmModel.local)),
                value: LlmModel.local,
                subtitle: ValueListenableBuilder<int?>(
                  valueListenable: localModelDownload,
                  builder: (context, percent, _) {
                    if (percent == null) {
                      return const Text('Works offline, ~2 GB download');
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Downloading... $percent%'),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: percent / 100),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
