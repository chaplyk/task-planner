import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../collections.dart';
import '../gemma/download.dart';
import '../models/reminder.dart';
import '../place_types.dart';
import 'model_choice.dart';

const _systemInstruction =
    'You convert reminders into JSON. Reply with JSON only, no explanations.';

final activeBackendNotifier = ValueNotifier<String>('not loaded');

// Converts text into a JSON using LLM
class ReminderExtractor {
  InferenceModel? _localModel;
  GenerativeModel? _gemini;
  String categories = '';
  String locations = '';
  List<String> _lists = const [];

  // The user's category, place and list names, kept current by listeners. Fetching
  // them for every extraction cost three Firestore queries per call, and with live
  // suggestions a call happens on every pause in typing.
  _Names? _categoryNames, _locationNames, _listNames;

  Future<Reminder?> extract(String transcript) async {
    if (transcript.trim().isEmpty) return null;

    final categoryNames = _categoryNames ??= _Names(categoriesCollection());
    final locationNames = _locationNames ??= _Names(locationsCollection());
    final listNames = _listNames ??= _Names(listsCollection());
    categories = (await categoryNames.get()).join(', ');
    locations = (await locationNames.get()).join(', ');
    _lists = await listNames.get();

    final output = await _generate(_prompt(transcript));
    debugPrint('Model output: $output');
    final reminder = _validList(Reminder.tryParse(output, transcript: transcript));
    if (reminder == null) {
      await FirebaseCrashlytics.instance.recordError(
        Exception('LLM extraction error'),
        StackTrace.current,
        reason: 'Reminder extraction failed',
        // No reminder text or model output: they are the user's private content.
        information: [
          'backend: ${activeBackendNotifier.value}',
          'transcript length: ${transcript.length}',
          'model output length: ${output.length}',
          'model output has JSON: ${output.contains('{')}',
        ],
      );
    }
    return reminder;
  }

  /// Keeps the list only if it is one of the user's lists (matching its exact spelling).
  Reminder? _validList(Reminder? r) {
    if (r == null || r.list == null) return r;
    final match = _lists.where((l) => l.toLowerCase() == r.list!.toLowerCase()).firstOrNull;
    return match == r.list ? r : r.withList(match);
  }

  Future<String> _generate(String prompt) async {
    if (modelChoiceNotifier.value == LlmModel.local) {
      if (await isLocalModelInstalled()) return _generateLocal(prompt);
      debugPrint('Local model not installed yet, falling back to Gemini');
    } else {
      await _closeLocal();
    }
    return _generateGemini(prompt);
  }

  Future<String> _generateGemini(String prompt) async {
    _gemini ??= FirebaseAI.googleAI().generativeModel(
      model: geminiModel,
      systemInstruction: Content.system(_systemInstruction),
      generationConfig: GenerationConfig(
        temperature: 0.1,
        maxOutputTokens: 1024,
        responseMimeType: 'application/json',
      ),
    );
    activeBackendNotifier.value = 'gemini';
    debugPrint('Inference backend: gemini');
    final response = await _gemini!.generateContent([Content.text(prompt)]);
    return response.text ?? '';
  }

  Future<String> _generateLocal(String prompt) async {
    _localModel ??= await FlutterGemma.getActiveModel(maxTokens: 1024);

    final session = await _localModel!.createSession(
      temperature: 0.1,
      systemInstruction: _systemInstruction,
      maxOutputTokens: 256,
    );

    activeBackendNotifier.value = _localModel!.activeBackend!.name;
    debugPrint('Inference backend: ${activeBackendNotifier.value}');

    try {
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      return await session.getResponse();
    } finally {
      await session.close();
    }
  }

  Future<void> _closeLocal() async {
    await _localModel?.close();
    _localModel = null;
  }

  Future<void> close() async {
    for (final names in [_categoryNames, _locationNames, _listNames]) {
      await names?.close();
    }
    _categoryNames = _locationNames = _listNames = null;
    await _closeLocal();
  }

  // "grocery" (any supermarket, ...), "hardware" (...), "pharmacy" (...)
  static final _storeTypesPrompt = storeTypes.entries.map((e) => '"${e.key}" (${e.value.aiHint})').join(', ');

  String _prompt(String transcript) =>
      'Extract the task from the reminder into '
      '{"summary": "...", "when": null, "condition": null, "activity": null, '
      '"location": null, "locationEvent": null, "category": null, "list": null, "confidence": 0.0}.\n'
      'The summary is short and imperative, without any time or place.\n'

      'If time mentioned, fill the "when" accordingly.\n'
      'Today is ${DateTime.now().toIso8601String()}.\n'
      'The "when" is an ISO 8601 datetime, for example "2026-04-20T09:00:00".\n'

      'The "activity" represents what the user must be doing to trigger reminder. '
      'The "activity" is one of ${activities.join(', ')}. '
      'For example driving a car is IN_VEHICLE. '
      'Do not assume IN_VEHICLE unless user explicitly mentions driving or a car. '
      'Use null if no activity fits.\n'

      'The "location" is the place the user mentions. '
      'If it matches one of the saved places ($locations), use that exact name. '
      'If the user means a kind of store rather than a saved place, use one of these: $_storeTypesPrompt. '
      'Otherwise use the place name as the user said it, for example "gym". '
      'Use null if no place is mentioned. '

      'The "locationEvent" can be "enter" or "exit". '
      'When a location is set, use "enter" unless the user talks about leaving. '
      'Use null if the reminder is not tied to a location.\n'

      'The "condition" is the time or activity as said in the reminder. '
      'For example "tomorrow afternoon" or "next time I drive".\n'

      'The "category" is the type of task.\n'
      'The "category" is one of $categories or "other".\n'

      '${_lists.isEmpty ? 'The "list" is null.' : 'The "list" is the user\'s list this task belongs in, one of: ${_lists.map((l) => '"$l"').join(', ')}. '
          'Pick the list whose purpose best fits the task, for example groceries go in a shopping list. '
          'Use null if no list clearly fits.'}\n'

      'The "confidence" is how useful this reminder is from 0.0 to 1.0.\n'
      'The "confidence" is low when when it is vague or meaningless.\n\n'

      'Reminder: "$transcript"\n';
}

/// The `name` of every document in a collection, kept up to date by a listener.
class _Names {
  _Names(CollectionReference<Map<String, dynamic>> collection) {
    _sub = collection.snapshots().listen(
      (s) {
        _names = [for (final d in s.docs) d.data()['name'] as String? ?? ''].where((n) => n.isNotEmpty).toList();
        if (!_loaded.isCompleted) _loaded.complete();
      },
      onError: (Object e) {
        debugPrint('Loading names failed: $e');
        if (!_loaded.isCompleted) _loaded.complete();
      },
    );
  }

  late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> _sub;
  final _loaded = Completer<void>();
  List<String> _names = const [];

  /// The current names; waits only for the first load.
  Future<List<String>> get() async {
    await _loaded.future;
    return _names;
  }

  Future<void> close() => _sub.cancel();
}
