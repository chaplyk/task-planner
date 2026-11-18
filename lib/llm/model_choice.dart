import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The model that turns text into reminders. Cloud models carry their Gemini model id.
/// [gemini] keeps its old name because it is what users' saved choice refers to.
enum LlmModel {
  gemini('gemini-3.5-flash-lite'),
  gemini38Flash('gemini-3.8-flash'),
  geminiHydrogen('gemini-4-hydrogen'),
  local(null);

  const LlmModel(this.cloudId);

  final String? cloudId;

  bool get isCloud => cloudId != null;
}

/// The default cloud model, also used for emoji and when the local model isn't ready.
final geminiModel = LlmModel.gemini.cloudId!;

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
