import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'recurrence.dart';

const activities = ['IN_VEHICLE', 'ON_BICYCLE', 'RUNNING', 'WALKING'];

class Reminder {
  const Reminder({
    required this.summary,
    this.when,
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
  });
  final String summary;
  final DateTime? when;
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

  /// Set when this is a recurring task (saved as a routine, not a reminder); [when] is its first due time.
  final Recurrence? repeat;

  /// Same reminder in another list (null = Inbox).
  Reminder withList(String? list) => Reminder(
    summary: summary,
    when: when,
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
  );

  /// Same reminder with another category.
  Reminder withCategory(String? category) => Reminder(
    summary: summary,
    when: when,
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
  );

  // Parse a decoded JSON map. Model output is untrusted: any field may be missing or of the wrong type.
  factory Reminder.fromJson(Map<String, dynamic> json, {String? transcript}) {
    String? text(String key) {
      final v = json[key];
      return v is String && v.trim().isNotEmpty ? v : null;
    }

    final summary = json['summary'];
    final parsedWhen = json['when'] is String ? DateTime.tryParse(json['when']) : null;
    final condition = text('condition');
    final category = text('category');
    final list = text('list');
    final rawConfidence = json['confidence'];
    final confidence = rawConfidence is num ? rawConfidence.toDouble() : null; // models also write 1 for 1.0
    final String? activity = activities.contains(json['activity']) ? json['activity'] : null;
    final location = text('location');
    final String? locationEvent = ['enter', 'exit'].contains(json['locationEvent']) ? json['locationEvent'] : null;
    // An activity trigger wins over a time; keeping both would let the time be scheduled later.
    final when = activity == null ? parsedWhen : null;
    final repeat = Recurrence.tryParse(json['repeat']);

    String triggerType;
    if (repeat != null) {
      triggerType = 'repeat';
    } else if (activity != null) {
      triggerType = 'activity';
    } else if (when != null) {
      triggerType = 'time';
    } else if (location != null && locationEvent != null) {
      triggerType = 'location';
    } else {
      triggerType = 'none';
    }

    return Reminder(
      summary: summary is String ? summary : '',
      when: when,
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
    );
  }

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'when': when?.toIso8601String(),
    'condition': condition,
    'activity': activity,
    'location': location,
    'locationEvent': locationEvent,
    'category': category,
    'list': list,
    'confidence': confidence,
    'notified': notified,
    'repeat': repeat?.toMap(),
  };

  Map<String, dynamic> toMap() => {
    'summary': summary,
    'when': when == null ? null : Timestamp.fromDate(when!),
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
      'Reminder(summary: $summary, when: $when, condition: $condition, '
      'transcript: $transcript, triggerType: $triggerType, activity: $activity, '
      'location: $location, locationEvent: $locationEvent, '
      'category: $category, list: $list, confidence: $confidence, notified: $notified, repeat: $repeat)';
}
