import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nagadai/gemma/download.dart';
import 'package:nagadai/llm/extractor.dart';
import 'package:nagadai/llm/model_choice.dart';

const _transcript =
    "Remind me to buy a milk tomorrow afternoon because I will be baking a cake "
    "for my daugter's birthday and will throw a party, inviting some friends like Bed and James over.";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> runExtraction() async {
    final reminder = await ReminderExtractor().extract(_transcript);

    debugPrint('backend: ${activeBackendNotifier.value}');
    debugPrint('summary: ${reminder?.summary}');
    debugPrint('from: ${reminder?.from}');
    debugPrint('to: ${reminder?.to}');
    debugPrint('when_string: ${reminder?.condition}');

    expect(reminder, isNotNull);
  }

  test('extracts a reminder with Gemini', timeout: Timeout.none, () async {
    modelChoiceNotifier.value = LlmModel.gemini;
    await runExtraction();
    expect(activeBackendNotifier.value, geminiModel);
  });

  test('extracts a reminder with local model', timeout: Timeout.none, () async {
    await FlutterEdgeAi.initialize(inferenceEngines: [LiteRtLmEngine()]);
    await downloadModel();
    modelChoiceNotifier.value = LlmModel.local;
    await runExtraction();
    expect(activeBackendNotifier.value, isNot(startsWith('gemini')));
  });
}
