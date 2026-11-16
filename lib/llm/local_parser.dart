// Instant, on-device trigger suggestions for the smart input.
// Pure Dart and synchronous so it can run on every keystroke; AI refines later.

import '../place_types.dart';

enum SuggestionKind { time, activity, location, category }

enum SuggestionSource { local, ai, manual }

const activityConditions = {
  'IN_VEHICLE': 'next time I drive',
  'ON_BICYCLE': 'next time I cycle',
  'RUNNING': 'next time I run',
  'WALKING': 'next time I walk',
};

const activityEmoji = {'IN_VEHICLE': '🚗', 'ON_BICYCLE': '🚲', 'RUNNING': '🏃', 'WALKING': '🚶'};

class Suggestion {
  const Suggestion({
    required this.kind,
    this.source = SuggestionSource.local,
    this.when,
    this.activity,
    this.location,
    this.locationEvent,
    this.category,
    this.spans = const [],
  });

  final SuggestionKind kind;
  final SuggestionSource source;
  final DateTime? when;
  final String? activity;
  final String? location;
  final String? locationEvent;
  final String? category;

  /// Character ranges of the input that this suggestion was read from.
  final List<(int, int)> spans;

  bool get isTrigger => kind != SuggestionKind.category;

  String get triggerType => switch (kind) {
    SuggestionKind.time => 'time',
    SuggestionKind.activity => 'activity',
    SuggestionKind.location => 'location',
    SuggestionKind.category => 'none',
  };

  String get emoji => switch (kind) {
    SuggestionKind.time => '⏰',
    SuggestionKind.activity => activityEmoji[activity] ?? '🏃',
    SuggestionKind.location => storeTypes[location]?.emoji ?? '📍',
    SuggestionKind.category => '🏷️',
  };

  /// Human-readable condition for activity/location; time is formatted by the UI.
  String? get condition => switch (kind) {
    SuggestionKind.activity => activityConditions[activity],
    SuggestionKind.location =>
      isStoreType(location)
          ? storeCondition(location!, locationEvent)
          : locationEvent == 'exit'
          ? 'when I leave $location'
          : 'when I arrive at $location',
    _ => null,
  };

  /// Same trigger regardless of where it came from.
  bool sameAs(Suggestion o) =>
      kind == o.kind &&
      activity == o.activity &&
      location == o.location &&
      locationEvent == o.locationEvent &&
      category == o.category &&
      (when == null) == (o.when == null) &&
      (when == null || when!.difference(o.when!).inMinutes.abs() < 1);

  Suggestion withSource(SuggestionSource s) => Suggestion(
    kind: kind,
    source: s,
    when: when,
    activity: activity,
    location: location,
    locationEvent: locationEvent,
    category: category,
    spans: spans,
  );
}

const _weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

const _dayParts = {'morning': 9, 'afternoon': 14, 'evening': 19, 'night': 20};

const _activityPatterns = {
  'IN_VEHICLE': r'driv(?:e|ing)|car|commut(?:e|ing)',
  'ON_BICYCLE': r'bik(?:e|ing)|cycl(?:e|ing)',
  'RUNNING': r'run(?:ning)?|jog(?:ging)?',
  'WALKING': r'walk(?:ing)?',
};

const _categorySynonyms = {
  'work': ['office', 'boss', 'meeting', 'email', 'client', 'report', 'deadline', 'colleague'],
  'family': [
    'mom',
    'mum',
    'dad',
    'kids',
    'son',
    'daughter',
    'wife',
    'husband',
    'grandma',
    'grandpa',
    'sister',
    'brother',
  ],
  'shopping': ['buy', 'groceries', 'grocery', 'milk', 'store', 'shop', 'order'],
  'health': ['doctor', 'dentist', 'pills', 'medicine', 'vitamins', 'pharmacy', 'gym', 'workout'],
  'finance': ['pay', 'bills', 'bank', 'rent', 'tax', 'taxes', 'invoice'],
  'home': ['laundry', 'clean', 'dishes', 'trash', 'plants', 'vacuum'],
  'personal': ['call', 'birthday', 'book', 'read'],
};

/// Suggests triggers (time, activity, place) and a category for [text].
/// Trigger suggestions come first, most specific first.
List<Suggestion> suggestTriggers(
  String text, {
  List<String> places = const [],
  List<String> categories = const [],
  DateTime? now,
}) {
  final lower = text.toLowerCase();
  final result = <Suggestion>[];
  final time = _parseTime(lower, now ?? DateTime.now());
  if (time != null) result.add(time);
  result.addAll(_parseLocations(lower, places));
  final activity = _parseActivity(lower);
  if (activity != null) result.add(activity);
  final category = _parseCategory(lower, categories);
  if (category != null) result.add(category);
  return result;
}

Suggestion? _parseTime(String s, DateTime now) {
  final spans = <(int, int)>[];
  DateTime? day;
  int? hour, minute;

  // "in 20 minutes", "in 2 hours", "in 3 days"
  final rel = RegExp(r'\bin\s+(\d{1,3}|an?|one|two|three)\s+(minute|min|hour|hr|day)s?\b').firstMatch(s);
  if (rel != null) {
    final raw = rel.group(1)!;
    final n = switch (raw) {
      'a' || 'an' || 'one' => 1,
      'two' => 2,
      'three' => 3,
      _ => int.parse(raw),
    };
    final unit = rel.group(2)!;
    final d = unit.startsWith('min')
        ? Duration(minutes: n)
        : unit.startsWith('h')
        ? Duration(hours: n)
        : Duration(days: n);
    return Suggestion(kind: SuggestionKind.time, when: now.add(d), spans: [(rel.start, rel.end)]);
  }

  // "at 6", "at 6:30pm", "at 18:00"
  final at = RegExp(r'\b(?:at|by|@)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?(?=\W|$)').firstMatch(s);
  if (at != null) {
    var h = int.parse(at.group(1)!);
    final m = int.tryParse(at.group(2) ?? '') ?? 0;
    final suffix = at.group(3)?.replaceAll('.', '');
    if (h <= 23 && m <= 59) {
      if (suffix == 'pm' && h < 12) h += 12;
      if (suffix == 'am' && h == 12) h = 0;
      if (suffix == null && h >= 1 && h <= 7) h += 12; // "at 6" means evening
      hour = h;
      minute = m;
      spans.add((at.start, at.end));
    }
  }

  // Day parts: "tomorrow morning", "this evening", "tonight"
  final part = RegExp(r'\b(?:this\s+)?(morning|afternoon|evening|night)\b').firstMatch(s);
  if (part != null && hour == null) {
    hour = _dayParts[part.group(1)];
    minute = 0;
    spans.add((part.start, part.end));
  }

  final tonight = RegExp(r'\btonight\b').firstMatch(s);
  final tomorrow = RegExp(r'\b(?:tomorrow|tmrw|tmr)\b').firstMatch(s);
  final today = RegExp(r'\btoday\b').firstMatch(s);
  final nextWeek = RegExp(r'\bnext\s+week\b').firstMatch(s);
  final weekday = RegExp(r'\b(?:on\s+|next\s+|this\s+)?(' + _weekdays.join('|') + r')\b').firstMatch(s);
  final base = DateTime(now.year, now.month, now.day);

  if (tomorrow != null) {
    day = base.add(const Duration(days: 1));
    spans.add((tomorrow.start, tomorrow.end));
  } else if (tonight != null) {
    day = base;
    hour ??= 20;
    minute ??= 0;
    spans.add((tonight.start, tonight.end));
  } else if (today != null) {
    day = base;
    spans.add((today.start, today.end));
  } else if (nextWeek != null) {
    day = base.add(Duration(days: 8 - now.weekday)); // next Monday
    spans.add((nextWeek.start, nextWeek.end));
  } else if (weekday != null) {
    final target = _weekdays.indexOf(weekday.group(1)!) + 1;
    var diff = (target - now.weekday) % 7;
    if (diff == 0) diff = 7;
    day = base.add(Duration(days: diff));
    spans.add((weekday.start, weekday.end));
  }

  if (day == null && hour == null) return null;

  if (day == null) {
    // Only a time: today, or tomorrow if it has passed.
    var candidate = DateTime(now.year, now.month, now.day, hour!, minute ?? 0);
    if (!candidate.isAfter(now)) candidate = candidate.add(const Duration(days: 1));
    return Suggestion(kind: SuggestionKind.time, when: candidate, spans: spans);
  }

  var when = DateTime(day.year, day.month, day.day, hour ?? 9, minute ?? 0);
  if (hour == null && day == base) {
    // "today" without a time: this evening, or an hour from now if that has passed.
    when = DateTime(day.year, day.month, day.day, 18);
    if (!when.isAfter(now)) when = now.add(const Duration(hours: 1));
  }
  if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
  return Suggestion(kind: SuggestionKind.time, when: when, spans: spans);
}

Suggestion? _parseActivity(String s) {
  for (final MapEntry(key: activity, value: pattern) in _activityPatterns.entries) {
    final m = RegExp(
      r'\b(?:(?:the\s+)?next\s+time\s+(?:i\s+)?(?:am\s+|go\s+|start\s+)?|when(?:ever)?\s+i(?:\s+am|\s+go|\s+start|\s+get\s+in(?:to)?\s+(?:the\s+|my\s+)?)?\s*|while\s+(?:i\s+am\s+)?|in\s+the\s+)?(?:' +
          pattern +
          r')\b',
    ).firstMatch(s);
    if (m != null) {
      return Suggestion(kind: SuggestionKind.activity, activity: activity, spans: [(m.start, m.end)]);
    }
  }
  return null;
}

List<Suggestion> _parseLocations(String s, List<String> places) {
  final result = <Suggestion>[];
  // Saved places first, so a saved place called "market" wins over the store type.
  for (final place in places) {
    final name = place.toLowerCase().trim();
    if (name.isEmpty) continue;
    final m = RegExp(r'\b' + RegExp.escape(name) + r'\b').firstMatch(s);
    if (m != null) result.add(_placeSuggestion(s, m, place));
  }
  // Kinds of stores: "at the supermarket" -> any grocery store.
  for (final MapEntry(:key, :value) in storeTypes.entries) {
    if (result.any((r) => r.location == key)) continue;
    final keywords = [...value.keywords]..sort((a, b) => b.length.compareTo(a.length));
    for (final k in keywords) {
      final m = RegExp(r'\b' + RegExp.escape(k) + r'\b').firstMatch(s);
      if (m == null) continue;
      final overlapsSaved = result.any((r) => r.spans.any((sp) => m.start < sp.$2 && sp.$1 < m.end));
      if (!overlapsSaved) result.add(_placeSuggestion(s, m, key));
      break;
    }
  }
  return result;
}

Suggestion _placeSuggestion(String s, RegExpMatch m, String location) {
  final windowStart = (m.start - 30).clamp(0, s.length);
  final before = s.substring(windowStart, m.start);
  final exit = RegExp(r'\b(leave|leaving|exit|get out of|out of|depart)\b').hasMatch(before);
  // Extend the span back to "when I ..." so it can be stripped from the summary.
  final lead = RegExp(
    r'\b(?:when(?:ever)?\s+i\s+|once\s+i\s+|as\s+soon\s+as\s+i\s+|at\s+|to\s+|from\s+|in\s+)',
  ).allMatches(before);
  final start = lead.isEmpty ? m.start : windowStart + lead.last.start;
  return Suggestion(
    kind: SuggestionKind.location,
    location: location,
    locationEvent: exit ? 'exit' : 'enter',
    spans: [(start, m.end)],
  );
}

Suggestion? _parseCategory(String s, List<String> categories) {
  for (final category in categories) {
    final name = category.toLowerCase();
    final words = [name, ...?_categorySynonyms[name]];
    for (final w in words) {
      if (RegExp(r'\b' + RegExp.escape(w) + r'\b').hasMatch(s)) {
        return Suggestion(kind: SuggestionKind.category, category: category);
      }
    }
  }
  return null;
}

const _leadPhrases = [
  'remind me to ',
  'remind me about ',
  'remind me ',
  "don't forget to ",
  'dont forget to ',
  'i need to ',
  'need to ',
];

const _danglers = {
  'when',
  'at',
  'on',
  'in',
  'by',
  'to',
  'and',
  'the',
  'next',
  'time',
  'i',
  'whenever',
  'once',
  'this',
  'from',
  'while',
  'as',
  'soon',
};

/// Builds a short imperative summary by stripping the lead phrase and trigger words.
String cleanSummary(String text, Iterable<(int, int)> spans) {
  final sorted = spans.toList()..sort((a, b) => b.$1.compareTo(a.$1));
  var s = text;
  for (final (start, end) in sorted) {
    if (start < 0 || end > s.length || start >= end) continue;
    s = s.replaceRange(start, end, ' ');
  }
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  final lower = s.toLowerCase();
  for (final lead in _leadPhrases) {
    if (lower.startsWith(lead)) {
      s = s.substring(lead.length);
      break;
    }
  }
  // Drop dangling connector words and punctuation at the end.
  var words = s.split(' ').where((w) => w.isNotEmpty).toList();
  while (words.isNotEmpty &&
      (_danglers.contains(words.last.toLowerCase().replaceAll(RegExp(r'[^\w]'), '')) ||
          RegExp(r'^[^\w]+$').hasMatch(words.last))) {
    words.removeLast();
  }
  s = words.join(' ').replaceAll(RegExp(r'[\s,.;:!?-]+$'), '');
  if (s.isEmpty) return text.trim();
  return s[0].toUpperCase() + s.substring(1);
}
