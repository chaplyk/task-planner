// Instant, on-device trigger suggestions for the smart input.
// Pure Dart and synchronous so it can run on every keystroke; AI refines later.

import '../models/recurrence.dart';
import '../place_types.dart';

enum SuggestionKind { time, activity, location, category, repeat }

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
    this.from,
    this.to,
    this.activity,
    this.location,
    this.locationEvent,
    this.category,
    this.repeat,
    this.spans = const [],
  });

  final SuggestionKind kind;
  final SuggestionSource source;
  /// When it starts; for a repeat, its first due time.
  final DateTime? from;

  /// When it ends, for a time range or a stated length.
  final DateTime? to;
  final String? activity;
  final String? location;
  final String? locationEvent;
  final String? category;

  /// How often a [SuggestionKind.repeat] task comes back; [from] is then its first due time.
  final Recurrence? repeat;

  /// Character ranges of the input that this suggestion was read from.
  final List<(int, int)> spans;

  bool get isTrigger => kind != SuggestionKind.category;

  String get triggerType => switch (kind) {
    SuggestionKind.time => 'time',
    SuggestionKind.activity => 'activity',
    SuggestionKind.location => 'location',
    SuggestionKind.category => 'none',
    SuggestionKind.repeat => 'repeat',
  };

  String get emoji => switch (kind) {
    SuggestionKind.time => '⏰',
    SuggestionKind.activity => activityEmoji[activity] ?? '🏃',
    SuggestionKind.location => storeTypes[location]?.emoji ?? '📍',
    SuggestionKind.category => '🏷️',
    SuggestionKind.repeat => '🔁',
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
    SuggestionKind.repeat => repeat?.label,
    _ => null,
  };

  /// Same trigger regardless of where it came from.
  bool sameAs(Suggestion o) =>
      kind == o.kind &&
      activity == o.activity &&
      location == o.location &&
      locationEvent == o.locationEvent &&
      category == o.category &&
      repeat?.every == o.repeat?.every &&
      repeat?.unit == o.repeat?.unit &&
      _sameMoment(from, o.from) &&
      _sameMoment(to, o.to);

  static bool _sameMoment(DateTime? a, DateTime? b) =>
      (a == null) == (b == null) && (a == null || a.difference(b!).inMinutes.abs() < 1);

  Suggestion withSource(SuggestionSource s) => Suggestion(
    kind: kind,
    source: s,
    from: from,
    to: to,
    activity: activity,
    location: location,
    locationEvent: locationEvent,
    category: category,
    repeat: repeat,
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
  final repeat = _parseRepeat(lower, time);
  if (repeat != null) {
    result.add(repeat);
  } else if (time != null) {
    result.add(time);
  }
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
  // The end of a range: a time of day, a number of days after the start day, or a length.
  int? endHour, endMinute, endDayOffset;
  Duration? duration;

  // "for 2 hours", "for half an hour", "for 3 days": how long it lasts.
  final length = RegExp(r'\bfor\s+(half\s+an|\d{1,3}|an?|one|two|three)\s+(minute|min|hour|hr|day)s?\b').firstMatch(s);
  if (length != null) {
    final raw = length.group(1)!;
    final unit = length.group(2)!;
    if (raw.startsWith('half')) {
      duration = const Duration(minutes: 30);
    } else {
      final n = _count(raw);
      duration = unit.startsWith('min')
          ? Duration(minutes: n)
          : unit.startsWith('h')
          ? Duration(hours: n)
          : Duration(days: n);
    }
    spans.add((length.start, length.end));
  }

  // "in 20 minutes", "in 2 hours", "in 3 days"
  final rel = RegExp(r'\bin\s+(\d{1,3}|an?|one|two|three)\s+(minute|min|hour|hr|day)s?\b').firstMatch(s);
  if (rel != null) {
    final n = _count(rel.group(1)!);
    final unit = rel.group(2)!;
    final d = unit.startsWith('min')
        ? Duration(minutes: n)
        : unit.startsWith('h')
        ? Duration(hours: n)
        : Duration(days: n);
    final from = now.add(d);
    return Suggestion(
      kind: SuggestionKind.time,
      from: from,
      to: duration == null ? null : from.add(duration),
      spans: [...spans, (rel.start, rel.end)],
    );
  }

  // "from 2 to 3pm", "between 7 and 9", "5-7pm", "9:30-9:45"
  final range = RegExp(
    r'\b(?:(from|between|at)\s+)?' + _clock + r'\s*(?:to|and|until|till|-|–)\s*' + _clock + r'(?=\W|$)',
  ).firstMatch(s);
  if (range != null) {
    final lead = range.group(1);
    var (h1, m1, sfx1) = (int.parse(range.group(2)!), int.tryParse(range.group(3) ?? '') ?? 0, _suffix(range.group(4)));
    var (h2, m2, sfx2) = (int.parse(range.group(5)!), int.tryParse(range.group(6) ?? '') ?? 0, _suffix(range.group(7)));
    // Without a lead word, a suffix or minutes it is probably not a time ("buy 2 and 3 apples").
    final timeLike = lead != null || sfx1 != null || sfx2 != null || range.group(3) != null || range.group(6) != null;
    if (timeLike && h1 <= 23 && h2 <= 23 && m1 <= 59 && m2 <= 59) {
      final pickedStart = sfx1 ?? sfx2; // "5-7pm": the start shares the end's suffix
      h1 = _to24(h1, pickedStart, eveningGuess: true);
      h2 = _to24(h2, sfx2 ?? sfx1, eveningGuess: false);
      // "between 7 and 9" -> 19 to 21; "11 to 1" -> 11 to 13.
      if (sfx2 == null && h2 * 60 + m2 <= h1 * 60 + m1 && h2 < 12) h2 += 12;
      hour = h1;
      minute = m1;
      endHour = h2;
      endMinute = m2;
      spans.add((range.start, range.end));
    }
  }

  // "at 6", "at 6:30pm", "at 18:00"
  // Not a street address: "meet Sam at 5 Main Street".
  final at = hour != null
      ? null
      : RegExp(
          r'\b(?:at|by|@)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?(?=\W|$)'
          r'(?!\s+\w+\s+(?:street|st|avenue|ave|road|rd|boulevard|blvd|lane|ln|drive|dr|way|place|square)\b)',
        ).firstMatch(s);
  if (at != null) {
    final h = int.parse(at.group(1)!);
    final m = int.tryParse(at.group(2) ?? '') ?? 0;
    if (h <= 23 && m <= 59) {
      hour = _to24(h, _suffix(at.group(3)), eveningGuess: true); // "at 6" means evening
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

  final weekdays = _weekdays.join('|');
  final dayRange = RegExp(r'\b(?:from\s+)?(' + weekdays + r')\s*(?:to|until|till|through|-|–)\s*(' + weekdays + r')\b')
      .firstMatch(s);
  final tonight = RegExp(r'\btonight\b').firstMatch(s);
  final tomorrow = RegExp(r'\b(?:tomorrow|tmrw|tmr)\b').firstMatch(s);
  final today = RegExp(r'\btoday\b').firstMatch(s);
  final nextWeek = RegExp(r'\bnext\s+week\b').firstMatch(s);
  final weekday = RegExp(r'\b(?:on\s+|next\s+|this\s+)?(' + weekdays + r')\b').firstMatch(s);
  final base = DateTime(now.year, now.month, now.day);

  DateTime nextWeekday(String name) {
    final target = _weekdays.indexOf(name) + 1;
    var diff = (target - now.weekday) % 7;
    if (diff == 0) diff = 7;
    return base.add(Duration(days: diff));
  }

  if (dayRange != null) {
    // "from wednesday to friday": the first day, through the last.
    day = nextWeekday(dayRange.group(1)!);
    final first = _weekdays.indexOf(dayRange.group(1)!);
    final last = _weekdays.indexOf(dayRange.group(2)!);
    endDayOffset = (last - first) % 7;
    if (endDayOffset == 0) endDayOffset = 7;
    spans.add((dayRange.start, dayRange.end));
  } else if (tomorrow != null) {
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
    day = nextWeekday(weekday.group(1)!);
    spans.add((weekday.start, weekday.end));
  }

  if (day == null && hour == null) return null;

  final DateTime from;
  if (day == null) {
    // Only a time: today, or tomorrow if it has passed.
    var candidate = DateTime(now.year, now.month, now.day, hour!, minute ?? 0);
    if (!candidate.isAfter(now)) candidate = candidate.add(const Duration(days: 1));
    from = candidate;
  } else {
    var start = DateTime(day.year, day.month, day.day, hour ?? 9, minute ?? 0);
    if (hour == null && day == base) {
      // "today" without a time: this evening, or an hour from now if that has passed.
      start = DateTime(day.year, day.month, day.day, 18);
      if (!start.isAfter(now)) start = now.add(const Duration(hours: 1));
    }
    if (!start.isAfter(now)) start = start.add(const Duration(days: 1));
    from = start;
  }

  DateTime? to;
  if (endHour != null || endDayOffset != null) {
    final offset = endDayOffset ?? 0;
    to = DateTime(from.year, from.month, from.day + offset, endHour ?? 18, endMinute ?? 0);
    // A time range past midnight ends the next day.
    if (!to.isAfter(from)) to = to.add(const Duration(days: 1));
  } else if (duration != null) {
    to = from.add(duration);
  }
  return Suggestion(kind: SuggestionKind.time, from: from, to: to, spans: spans);
}

/// A clock time: hour, optional minutes, optional am/pm (three groups).
const _clock = r'(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?';

String? _suffix(String? raw) => raw?.replaceAll('.', '');

/// [h] in 24-hour time. Without a suffix, 1–7 is read as evening when [eveningGuess] ("at 6" = 18:00).
int _to24(int h, String? suffix, {required bool eveningGuess}) {
  if (suffix == 'pm' && h < 12) return h + 12;
  if (suffix == 'am' && h == 12) return 0;
  if (suffix == null && eveningGuess && h >= 1 && h <= 7) return h + 12;
  return h;
}

int _count(String raw) => switch (raw) {
  'a' || 'an' || 'one' => 1,
  'two' => 2,
  'three' => 3,
  _ => int.parse(raw),
};

const _numberWords = {'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'other': 2};

/// "every 3 days", "every other week", "daily", "every monday at 9", "every morning".
/// A [time] found in the same text becomes the first due time and makes the schedule fixed.
Suggestion? _parseRepeat(String s, Suggestion? time) {
  int? every;
  String? unit;
  RegExpMatch? m;

  m = RegExp(r'\bevery\s+(?:(\d{1,3}|other|a|an|one|two|three|four|five|six)\s+)?(hour|day|week|month)s?\b').firstMatch(s);
  if (m != null) {
    final raw = m.group(1);
    every = raw == null ? 1 : (int.tryParse(raw) ?? _numberWords[raw]);
    unit = m.group(2);
  }
  if (unit == null) {
    m = RegExp(r'\b(hourly|daily|weekly|monthly|biweekly|fortnightly|every\s+fortnight)\b').firstMatch(s);
    if (m != null) {
      (every, unit) = switch (m.group(1)!) {
        'hourly' => (1, 'hour'),
        'daily' => (1, 'day'),
        'weekly' => (1, 'week'),
        'monthly' => (1, 'month'),
        _ => (2, 'week'),
      };
    }
  }
  if (unit == null) {
    m = RegExp(r'\bevery\s+(' + _weekdays.join('|') + r')\b').firstMatch(s);
    if (m != null) (every, unit) = (1, 'week');
  }
  if (unit == null) {
    m = RegExp(r'\bevery\s+(morning|afternoon|evening|night)\b').firstMatch(s);
    if (m != null) (every, unit) = (1, 'day');
  }
  if (m == null || unit == null || every == null || every < 1) return null;

  return Suggestion(
    kind: SuggestionKind.repeat,
    repeat: Recurrence(every: every, unit: unit, mode: time != null ? Recurrence.modeFixed : Recurrence.modeDone),
    from: time?.from,
    spans: [(m.start, m.end), ...?time?.spans],
  );
}

Suggestion? _parseActivity(String s) {
  for (final MapEntry(key: activity, value: pattern) in _activityPatterns.entries) {
    // The lead-in ("next time I", "when I", "while") is required: a bare "walk the dog"
    // or "run the dishwasher" is the task itself, not a trigger.
    final m = RegExp(
      r'\b(?:(?:the\s+)?next\s+time\s+(?:i\s+)?(?:am\s+|go\s+|start\s+)?|when(?:ever)?\s+i(?:\s+am|\s+go|\s+start|\s+get\s+in(?:to)?\s+(?:the\s+|my\s+)?)?\s*|while\s+(?:i\s+am\s+)?|in\s+the\s+)(?:' +
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
      final m = RegExp(r'\b' + RegExp.escape(k) + r'\b').allMatches(s).where((m) => _isStorePlace(s, m)).firstOrNull;
      if (m == null) continue;
      final overlapsSaved = result.any((r) => r.spans.any((sp) => m.start < sp.$2 && sp.$1 < m.end));
      if (!overlapsSaved) result.add(_placeSuggestion(s, m, key));
      break;
    }
  }
  return result;
}

const _article = r'(?:the\s+|a\s+|an\s+|my\s+)?$';

/// "at the", "leaving the": the store keyword right after it is somewhere to be.
final _storeLead = RegExp(
  r'\b(?:at|in|inside|near|from|leave|leaving|exit|exiting|out\s+of|pass|passing|reach)\s+' + _article,
);

/// "when I get to the", "next time I am near a": a condition that ends at the store keyword.
final _storeCondition = RegExp(
  r'\b(?:when(?:ever)?|next\s+time|once|as\s+soon\s+as)\s+i\b[^.,;]*?\s' + _article,
);

/// Whether a store keyword is used as a place ("at the supermarket") rather than
/// as part of the task ("buy groceries", "call the pharmacy", "the stock market").
bool _isStorePlace(String s, RegExpMatch m) {
  final before = s.substring(0, m.start);
  return _storeLead.hasMatch(before) || _storeCondition.hasMatch(before);
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
  'every',
  'until',
  'till',
  'between',
  'for',
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
