import 'package:flutter_test/flutter_test.dart';
import 'package:nagadai/llm/local_parser.dart';
import 'package:nagadai/models/recurrence.dart';

// Monday, 16 Nov 2026, 10:00
final _now = DateTime(2026, 11, 16, 10);

Suggestion? _trigger(String text, {List<String> places = const []}) {
  final s = suggestTriggers(text, places: places, categories: const ['work', 'family'], now: _now);
  return s.where((x) => x.isTrigger).firstOrNull;
}

void main() {
  group('time', () {
    test('tomorrow at 6 means 6 PM tomorrow', () {
      final t = _trigger('call mom tomorrow at 6')!;
      expect(t.kind, SuggestionKind.time);
      expect(t.when, DateTime(2026, 11, 17, 18));
    });

    test('tomorrow morning', () {
      expect(_trigger('do laundry tomorrow morning')!.when, DateTime(2026, 11, 17, 9));
    });

    test('tonight', () {
      expect(_trigger('take out trash tonight')!.when, DateTime(2026, 11, 16, 20));
    });

    test('in 2 hours', () {
      expect(_trigger('check the oven in 2 hours')!.when, DateTime(2026, 11, 16, 12));
    });

    test('at 9am rolls to tomorrow when passed', () {
      expect(_trigger('standup at 9am')!.when, DateTime(2026, 11, 17, 9));
    });

    test('weekday means next occurrence', () {
      expect(_trigger('pay rent on friday')!.when, DateTime(2026, 11, 20, 9));
      expect(_trigger('gym monday at 7pm')!.when, DateTime(2026, 11, 23, 19));
    });
  });

  group('activity', () {
    test('next time I run', () {
      final t = _trigger('stretch next time I run')!;
      expect(t.kind, SuggestionKind.activity);
      expect(t.activity, 'RUNNING');
    });

    test('driving', () {
      expect(_trigger('buy dog food next time I am driving')!.activity, 'IN_VEHICLE');
    });
  });

  group('location', () {
    test('leave office is an exit', () {
      final t = _trigger('buy milk when I leave office', places: ['office'])!;
      expect(t.kind, SuggestionKind.location);
      expect(t.location, 'office');
      expect(t.locationEvent, 'exit');
    });

    test('get home is an enter', () {
      final t = _trigger('pay bills when I get home', places: ['Home'])!;
      expect(t.location, 'Home');
      expect(t.locationEvent, 'enter');
    });
  });

  group('store types', () {
    test('supermarket means any grocery store', () {
      final t = _trigger('buy milk at the supermarket')!;
      expect(t.kind, SuggestionKind.location);
      expect(t.location, 'grocery');
      expect(t.condition, 'at the grocery store');
    });

    test('pharmacy and hardware', () {
      expect(_trigger('pick up pills at the drugstore')!.location, 'pharmacy');
      expect(_trigger('get screws in the hardware store')!.location, 'hardware');
    });

    test('a saved place wins over the store type', () {
      expect(_trigger('buy apples at the market', places: ['Market'])!.location, 'Market');
    });

    test('store phrase is stripped from the summary', () {
      const text = 'buy milk at the supermarket';
      final s = suggestTriggers(text, now: _now);
      expect(cleanSummary(text, s.expand((x) => x.spans)), 'Buy milk');
    });
  });

  group('words that are the task, not a trigger', () {
    test('activity words without a lead-in', () {
      expect(_trigger('Remind me to walk the dog'), isNull);
      expect(_trigger('run the dishwasher'), isNull);
      expect(_trigger('buy a car seat for the baby'), isNull);
      expect(_trigger('go for a run tomorrow at 7am')!.kind, SuggestionKind.time);
    });

    test('store words that are not a place to be', () {
      expect(_trigger('buy groceries'), isNull);
      expect(_trigger('check the stock market'), isNull);
      expect(_trigger('fix the hardware issue on my laptop'), isNull);
      expect(_trigger('call the pharmacy about my prescription'), isNull);
      expect(_trigger('go to the pharmacy'), isNull);
    });

    test('store words after a condition still count', () {
      expect(_trigger('buy milk when I get to the supermarket')!.location, 'grocery');
      final leave = _trigger('call mom when I leave the pharmacy')!;
      expect(leave.location, 'pharmacy');
      expect(leave.locationEvent, 'exit');
    });

    test('a street number is not a time', () {
      expect(_trigger('meet Sam at 5 Main Street'), isNull);
      expect(_trigger('meet Sam at 5')!.when, DateTime(2026, 11, 16, 17));
    });
  });

  test('no trigger', () {
    expect(_trigger('pay bills'), isNull);
  });

  test('category from name and synonym', () {
    List<Suggestion> s(String t) => suggestTriggers(t, categories: const ['work', 'family'], now: _now);
    expect(s('meeting notes for work').last.category, 'work');
    expect(s('call mom').last.category, 'family');
  });

  group('cleanSummary', () {
    String clean(String text, {List<String> places = const []}) {
      final s = suggestTriggers(text, places: places, now: _now);
      return cleanSummary(text, s.expand((x) => x.spans));
    }

    test('strips lead phrase and time', () {
      expect(clean('Remind me to call mom tomorrow at 6'), 'Call mom');
    });

    test('strips activity phrase', () {
      expect(clean('stretch next time I run'), 'Stretch');
    });

    test('strips place phrase', () {
      expect(clean('buy milk when I leave office', places: ['office']), 'Buy milk');
    });
  });

  group('repeat', () {
    Suggestion repeat(String text) => _trigger(text)!;
    String summary(String text) =>
        cleanSummary(text, suggestTriggers(text, now: _now).where((s) => s.isTrigger).expand((s) => s.spans));

    test('every 3 days counts from completion', () {
      final t = repeat('water plants every 3 days');
      expect(t.kind, SuggestionKind.repeat);
      expect(t.repeat, const Recurrence(every: 3, unit: 'day'));
      expect(t.when, isNull);
      expect(summary('water plants every 3 days'), 'Water plants');
    });

    test('every other day', () {
      expect(repeat('gym every other day').repeat, const Recurrence(every: 2, unit: 'day'));
    });

    test('monthly and biweekly', () {
      expect(repeat('pay rent monthly').repeat, const Recurrence(every: 1, unit: 'month'));
      expect(repeat('clean the fridge biweekly').repeat, const Recurrence(every: 2, unit: 'week'));
      expect(summary('pay rent monthly'), 'Pay rent');
    });

    test('every monday at 9 is a fixed weekly schedule starting next monday', () {
      final t = repeat('standup every monday at 9');
      expect(t.repeat, const Recurrence(every: 1, unit: 'week', mode: Recurrence.modeFixed));
      expect(t.when, DateTime(2026, 11, 23, 9));
      expect(summary('standup every monday at 9'), 'Standup');
    });

    test('every morning is a fixed daily schedule', () {
      final t = repeat('take meds every morning');
      expect(t.repeat, const Recurrence(every: 1, unit: 'day', mode: Recurrence.modeFixed));
      expect(t.when, DateTime(2026, 11, 17, 9));
      expect(summary('take meds every morning'), 'Take meds');
    });

    test('a plain time is not a repeat', () {
      expect(repeat('call mom tomorrow at 6').kind, SuggestionKind.time);
    });
  });
}
