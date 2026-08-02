import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

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
    this.confidence,
    this.notified = false,
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
  final double? confidence;
  final bool notified;

  // Parse a decoded JSON map
  factory Reminder.fromJson(Map<String, dynamic> json, {String? transcript}) {
    final summary = json['summary'];
    final when = json['when'] is String ? DateTime.tryParse(json['when']) : null;
    final condition = json['condition'];
    final category = json['category'];
    final confidence = json['confidence'];
    final activity = activities.contains(json['activity']) ? json['activity'] : null;
    final location = json['location'];
    final locationEvent = ['enter', 'exit'].contains(json['locationEvent']) ? json['locationEvent']: null;

    String triggerType;
    if (activity != null) {
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
      condition: condition is String && condition.isNotEmpty
          ? condition
          : null,
      transcript: transcript,
      triggerType: triggerType,
      activity: activity,
      location: location,
      locationEvent: locationEvent,
      category: category,
      confidence: confidence,
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
    'confidence': confidence,
    'notified': notified,
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
      'category: $category, confidence: $confidence, notified: $notified)';
}
