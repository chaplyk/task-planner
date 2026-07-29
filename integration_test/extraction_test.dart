import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:task_planner/model_download.dart';
import 'package:task_planner/reminder_extractor.dart';

const _transcript =
    "Remind me to buy a milk tomorrow afternoon because I will be baking a cake "
    "for my daugter's birthday and will throw a party, inviting some friends like Bed and James over.";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('extracts a reminder', timeout: Timeout.none, () async {
    await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
    await downloadModel();

    final reminder = await ReminderExtractor().extract(_transcript);

    debugPrint('summary: ${reminder?.summary}');
    debugPrint('when: ${reminder?.when}');
    debugPrint('when_string: ${reminder?.condition}');

    expect(reminder, isNotNull);
  });
}
