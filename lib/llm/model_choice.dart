import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LlmModel { gemini, local }

const _prefKey = 'llm_model';

final modelChoiceNotifier = ValueNotifier<LlmModel>(LlmModel.gemini);

Future<void> loadModelChoice() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_prefKey);
  modelChoiceNotifier.value = LlmModel.values.firstWhere(
    (m) => m.name == saved,
    orElse: () => LlmModel.gemini,
  );
}

Future<void> setModelChoice(LlmModel model) async {
  modelChoiceNotifier.value = model;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefKey, model.name);
}
