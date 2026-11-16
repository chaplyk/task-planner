import 'dart:math';

import 'package:flutter_gemma/flutter_gemma.dart';

final _random = Random();

const _prompt =
    'Make up a random reminder that person can say to voice assistant.'
    'It must mention one of the following: '
    'a time (like "tomorrow afternoon" or "next Monday at 1pm") or '
    'an activity (like "next time I drive"). '
    'Reply with just the spoken sentence, no explanations. '
    'For example: "Remind me to call mom tomorrow evening" or "Remind me to stretch next time I go for a run".';

Future<String> generateIdea() async {
  final model = await FlutterGemma.getActiveModel(maxTokens: 1024);
  final session = await model.createSession(
    temperature: 1.9,
    maxOutputTokens: 64,
    randomSeed: _random.nextInt(1 << 31),
  );
  try {
    await session.addQueryChunk(Message(text: _prompt, isUser: true));
    return (await session.getResponse()).trim();
  } finally {
    await session.close();
  }
}
