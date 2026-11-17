import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../llm/emoji.dart';
import 'recurrence.dart';

const activities = ['IN_VEHICLE', 'ON_BICYCLE', 'RUNNING', 'WALKING'];

class Reminder {
  const Reminder({
    required this.summary,
    this.from,
    this.to,
    this.condition,
    this.transcript,
    this.triggerType = 'time',
    this.activity,
    this.location,
    this.locationEvent,
    this.category,
    this.list,
    this.confidence,
    this.notified = false,
    this.repeat,
    this.emoji,
  });
  final String summary;
  /// When it starts (the notification fires then).
  final DateTime? from;

  /// When it ends, for event-like reminders ("2 to 3 pm"); null for a single moment.
  final DateTime? to;
  final String? condition;
  final String? transcript;
  final String triggerType;
  final String? activity;
  final String? location;
  final String? locationEvent;
  final String? category;

  /// Name of the user's list this task belongs to; null means the default Inbox.
  final String? list;
  final double? confidence;
  final bool notified;

  /// Set when this is a recurring task (saved as a routine, not a reminder); [from] is its first due time.
  final Recurrence? repeat;

  /// One emoji for the task: picked by the user, or by AI / keywords when null at save time.
  final String? emoji;

  /// Same reminder in another list (null = Inbox).
  Reminder withList(String? list) => Reminder(
    summary: summary,
    from: from,
    to: to,
    condition: condition,
    transcript: transcript,
    triggerType: triggerType,
    activity: activity,
    location: location,
    locationEvent: locationEvent,
    category: category,
    list: list,
    confidence: confidence,
    notified: notified,
    repeat: repeat,
    emoji: emoji,
  );

  /// Same reminder with another emoji.
  Reminder withEmoji(String? emoji) => Reminder(
    summary: summary,
    from: from,
    to: to,
    condition: condition,
    transcript: transcript,
    triggerType: triggerType,
    activity: activity,
    location: location,
    locationEvent: locationEvent,
    category: category,
    list: list,
    confidence: confidence,
    notified: notified,
    repeat: repeat,
    emoji: emoji,
  );

  /// Same reminder with another category.
  Reminder withCategory(String? category) => Reminder(
    summary: summary,
    from: from,
    to: to,
    condition: condition,
    transcript: transcript,
    triggerType: triggerType,
    activity: activity,
    location: location,
    locationEvent: locationEvent,
    category: category,
    list: list,
    confidence: confidence,
    notified: notified,
    repeat: repeat,
    emoji: emoji,
  );

  // Parse a decoded JSON map. Model output is untrusted: any field may be missing or of the wrong type.
  factory Reminder.fromJson(Map<String, dynamic> json, {String? transcript}) {
    String? text(String key) {
      final v = json[key];
      return v is String && v.trim().isNotEmpty ? v : null;
    }

    final summary = json['summary'];
    DateTime? date(String key) => json[key] is String ? DateTime.tryParse(json[key]) : null;
    // "when" is what the model was asked for before ranges existed.
    final parsedFrom = date('from') ?? date('when');
    final parsedTo = date('to');
    final condition = text('condition');
    final category = text('category');
    final list = text('list');
    final rawConfidence = json['confidence'];
    final confidence = rawConfidence is num ? rawConfidence.toDouble() : null; // models also write 1 for 1.0
    final String? activity = activities.contains(json['activity']) ? json['activity'] : null;
    final location = text('location');
    final String? locationEvent = ['enter', 'exit'].contains(json['locationEvent']) ? json['locationEvent'] : null;
    // An activity trigger wins over a time; keeping both would let the time be scheduled later.
    final from = activity == null ? parsedFrom : null;
    // An end only makes sense after a start.
    final to = from != null && parsedTo != null && parsedTo.isAfter(from) ? parsedTo : null;
    final repeat = Recurrence.tryParse(json['repeat']);
    final emoji = firstEmoji(json['emoji'] is String ? json['emoji'] : null);

    String triggerType;
    if (repeat != null) {
      triggerType = 'repeat';
    } else if (activity != null) {
      triggerType = 'activity';
    } else if (from != null) {
      triggerType = 'time';
    } else if (location != null && locationEvent != null) {
      triggerType = 'location';
    } else {
      triggerType = 'none';
    }

    return Reminder(
      summary: summary is String ? summary : '',
      from: from,
      to: to,
      condition: condition,
      transcript: transcript,
      triggerType: triggerType,
      activity: activity,
      location: location,
      locationEvent: locationEvent,
      category: category,
      list: list,
      confidence: confidence,
      repeat: repeat,
      emoji: emoji,
    );
  }

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'from': from?.toIso8601String(),
    'to': to?.toIso8601String(),
    'condition': condition,
    'activity': activity,
    'location': location,
    'locationEvent': locationEvent,
    'category': category,
    'list': list,
    'confidence': confidence,
    'notified': notified,
    'repeat': repeat?.toMap(),
    'emoji': emoji,
  };

  Map<String, dynamic> toMap() => {
    'summary': summary,
    'from': from == null ? null : Timestamp.fromDate(from!),
    'to': to == null ? null : Timestamp.fromDate(to!),
    'condition': condition,
    'transcript': transcript,
    'status': 0,
    'triggerType': triggerType,
    'activity': activity,
    'location': location,
    'locationEvent': locationEvent,
    'category': category,
    'list': list,
    'confidence': confidence,
    'notified': notified,
    'emoji': emoji,
    'createdAt': Timestamp.now(),
  };

  // Parse model output and transcript into Reminder
  static Reminder? tryParse(String raw, {String? transcript}) {
    final jsonSlice = _extractJsonObject(raw);
    if (jsonSlice == null) return null;
    try {
      final decoded = jsonDecode(jsonSlice);
      if (decoded is! Map<String, dynamic>) return null;
      final reminder = Reminder.fromJson(decoded, transcript: transcript);
      return reminder.summary.isEmpty ? null : reminder;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Returns the first balanced substring or null
  static String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    if (start == -1) return null;
    var depth = 0;
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (char == '{') depth++;
      if (char == '}') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  @override
  String toString() =>
      'Reminder(summary: $summary, from: $from, to: $to, condition: $condition, '
      'transcript: $transcript, triggerType: $triggerType, activity: $activity, '
      'location: $location, locationEvent: $locationEvent, '
      'category: $category, list: $list, confidence: $confidence, notified: $notified, repeat: $repeat, emoji: $emoji)';
}
