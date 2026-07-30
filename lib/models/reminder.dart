import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

const activities = ['IN_VEHICLE', 'ON_BICYCLE', 'RUNNING', 'WALKING', 'STILL'];

class Reminder {
  const Reminder({
    required this.summary,
    this.when,
    this.condition,
    this.transcript,
    this.triggerType = 'time',
    this.activity,
  });
  final String summary;
  final DateTime? when;
  final String? condition;
  final String? transcript;
  final String triggerType;
  final String? activity;

  // Parse a decoded JSON map
  factory Reminder.fromJson(Map<String, dynamic> json, {String? transcript}) {
    final dynamic summary = json['summary'];
    final dynamic when = json['when'];
    final dynamic condition = json['condition'];
    final activity = activities.contains(json['activity']) ? json['activity'] as String : null;
    return Reminder(
      summary: summary is String ? summary : '',
      when: when is String ? DateTime.tryParse(when) : null,
      condition: condition is String && condition.isNotEmpty
          ? condition
          : null,
      transcript: transcript,
      triggerType: activity == null ? 'time' : 'activity',
      activity: activity,
    );
  }

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'when': when?.toIso8601String(),
    'condition': condition,
    'activity': activity,
  };

  // Draft of Reminder object
  Map<String, dynamic> toMap() => {
    'summary': summary,
    'when': when == null ? null : Timestamp.fromDate(when!),
    'condition': condition,
    'transcript': transcript,
    'status': 0,
    'triggerType': triggerType,
    'activity': activity,
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
      'transcript: $transcript, triggerType: $triggerType, activity: $activity)';

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.summary == summary &&
      other.when == when &&
      other.condition == condition &&
      other.transcript == transcript &&
      other.triggerType == triggerType &&
      other.activity == activity;

  @override
  int get hashCode =>
      Object.hash(summary, when, condition, transcript, triggerType, activity);
}
