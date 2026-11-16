import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/widgets.dart';

import 'model_choice.dart';

const fallbackEmoji = '🏷️';

const _keywordEmoji = {
  'work': '💼',
  'job': '💼',
  'office': '💼',
  'home': '🏠',
  'house': '🏠',
  'chores': '🧹',
  'shopping': '🛒',
  'groceries': '🛒',
  'health': '🩺',
  'doctor': '🩺',
  'medicine': '💊',
  'gym': '🏋️',
  'sport': '🏋️',
  'fitness': '🏋️',
  'family': '👨‍👩‍👧',
  'kids': '🧸',
  'finance': '💰',
  'money': '💰',
  'bills': '🧾',
  'study': '📚',
  'school': '📚',
  'travel': '✈️',
  'car': '🚗',
  'personal': '🧑',
  'friends': '🫂',
  'pets': '🐾',
  'food': '🍽️',
  'hobby': '🎨',
};

final _lettersOrDigits = RegExp(r'[\p{L}\p{N}]', unicode: true);

GenerativeModel? _model;

/// Picks one emoji representing [category]. Tries Gemini first, then a keyword
/// map, then [fallbackEmoji]. Pass [avoid] to ask for a different emoji.
Future<String> suggestEmoji(String category, {String? avoid}) async {
  try {
    _model ??= FirebaseAI.googleAI().generativeModel(
      model: geminiModel,
      generationConfig: GenerationConfig(temperature: 0.4, maxOutputTokens: 16),
    );
    final prompt = StringBuffer(
      'Reply with exactly one emoji that best represents the reminder category "$category". '
      'No text, just the emoji.',
    );
    if (avoid != null) prompt.write(' Do not use $avoid.');
    final response = await _model!.generateContent([Content.text(prompt.toString())]);
    final emoji = _firstEmoji(response.text);
    if (emoji != null) return emoji;
    debugPrint('Gemini returned no usable emoji: ${response.text}');
  } catch (e) {
    debugPrint('Emoji suggestion failed: $e');
  }
  return keywordEmoji(category);
}

String keywordEmoji(String category) =>
    _keywordEmoji[category.trim().toLowerCase()] ?? fallbackEmoji;

String? _firstEmoji(String? text) {
  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final first = trimmed.characters.first;
  return _lettersOrDigits.hasMatch(first) ? null : first;
}
