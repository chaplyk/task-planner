import 'dart:convert';

class Reminder {
  const Reminder({required this.summary, this.when, this.whenString});
  final String summary;
  final DateTime? when;
  final String? whenString;

  /// Parse a decoded JSON map
  factory Reminder.fromJson(Map<String, dynamic> json) {
    final dynamic summary = json['summary'];
    final dynamic when = json['when'];
    final dynamic whenString = json['when_string'];
    return Reminder(
      summary: summary is String ? summary : '',
      when: when is String ? DateTime.tryParse(when) : null,
      whenString: whenString is String && whenString.isNotEmpty
          ? whenString
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'when': when?.toIso8601String(),
    'when_string': whenString,
  };

  /// Parses a raw model output string into a [Reminder]
  static Reminder? tryParse(String raw) {
    final jsonSlice = _extractJsonObject(raw);
    if (jsonSlice == null) return null;
    try {
      final decoded = jsonDecode(jsonSlice);
      if (decoded is! Map<String, dynamic>) return null;
      final reminder = Reminder.fromJson(decoded);
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
      'Reminder(summary: $summary, when: $when, whenString: $whenString)';

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.summary == summary &&
      other.when == when &&
      other.whenString == whenString;

  @override
  int get hashCode => Object.hash(summary, when, whenString);
}
