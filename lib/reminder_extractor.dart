import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'models/reminder.dart';

const _systemInstruction =
    'You convert reminders into JSON. Reply with JSON only, no explanations.';

// Converts text into a JSON using LLM
class ReminderExtractor {
  InferenceModel? _model;

  Future<Reminder?> extract(String transcript) async {
    if (transcript.trim().isEmpty) return null;

    _model ??= await FlutterGemma.getActiveModel(maxTokens: 1024);

    final session = await _model!.createSession(
      temperature: 0.1,
      systemInstruction: _systemInstruction,
      maxOutputTokens: 256,
    );
    try {
      await session.addQueryChunk(Message(text: _prompt(transcript), isUser: true));
      final raw = await session.getResponse();
      debugPrint('Model output: $raw');
      return Reminder.tryParse(raw, transcript: transcript);
    } finally {
      await session.close();
    }
  }

  Future<void> close() async {
    await _model?.close();
    _model = null;
  }

  String _prompt(String transcript) =>
      'Extract the task from the reminder into '
      '{"summary": "...", "when": null, "condition": null, "activity": null}.\n'
      'The summary is short and imperative, without any time or place.\n'
      'If time mentioned, fill the "when" accordingly.\n'
      'Today is ${DateTime.now().toIso8601String()}.\n'
      'The "when" is an ISO 8601 datetime, for example "2026-04-20T09:00:00".\n'
      'The "activity" represents what the user must be doing to trigger reminder. '
      'The "activity" is one of ${activities.join(', ')}. '
      'For example driving a car is IN_VEHICLE. '
      'Use null if no activity fits.\n'
      'The "condition" is the time or activity as said in the reminder. '
      'For example "tomorrow afternoon" or "next time I drive".\n\n'
      'Reminder: "$transcript"\n';
}
