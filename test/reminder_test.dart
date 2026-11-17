import 'package:flutter_test/flutter_test.dart';
import 'package:nagadai/models/recurrence.dart';
import 'package:nagadai/models/reminder.dart';

void main() {
  test('accepts a whole-number confidence', () {
    final r = Reminder.tryParse('{"summary": "Call mom", "confidence": 1}')!;
    expect(r.confidence, 1.0);
  });

  test('ignores fields of the wrong type instead of failing', () {
    final r = Reminder.tryParse(
      '{"summary": "Call mom", "category": ["family"], "location": 5, "list": {}, "condition": 3, "confidence": "high"}',
    )!;
    expect(r.summary, 'Call mom');
    expect(r.category, isNull);
    expect(r.location, isNull);
    expect(r.list, isNull);
    expect(r.condition, isNull);
    expect(r.confidence, isNull);
    expect(r.triggerType, 'none');
  });

  test('an activity trigger does not keep a time', () {
    final r = Reminder.tryParse('{"summary": "Stretch", "activity": "RUNNING", "when": "2026-11-17T09:00:00"}')!;
    expect(r.triggerType, 'activity');
    expect(r.from, isNull);
  });

  test('no summary or broken JSON gives null', () {
    expect(Reminder.tryParse('{"summary": 5}'), isNull);
    expect(Reminder.tryParse('{"summary": "x", }'), isNull);
    expect(Reminder.tryParse('sorry'), isNull);
  });

  test('parses a repeat and keeps the first due time', () {
    final r = Reminder.tryParse('{"summary": "Water plants", "repeat": {"every": 3, "unit": "day"}, "when": "2026-11-17T09:00:00"}')!;
    expect(r.repeat, const Recurrence(every: 3, unit: 'day'));
    expect(r.from, DateTime(2026, 11, 17, 9));
    expect(r.triggerType, 'repeat');
  });

  test('drops an invalid repeat', () {
    expect(Reminder.tryParse('{"summary": "x", "repeat": {"every": 2, "unit": "year"}}')!.repeat, isNull);
    expect(Reminder.tryParse('{"summary": "x", "repeat": "daily"}')!.repeat, isNull);
    expect(Reminder.tryParse('{"summary": "x", "repeat": null}')!.triggerType, 'none');
  });

  test('keeps one emoji from the model and drops anything else', () {
    expect(Reminder.tryParse('{"summary": "Water plants", "emoji": "🌱"}')!.emoji, '🌱');
    expect(Reminder.tryParse('{"summary": "Water plants", "emoji": "🌱 plants"}')!.emoji, '🌱');
    expect(Reminder.tryParse('{"summary": "Call mom", "emoji": "👨‍👩‍👧"}')!.emoji, '👨‍👩‍👧');
    expect(Reminder.tryParse('{"summary": "x", "emoji": ""}')!.emoji, isNull);
    expect(Reminder.tryParse('{"summary": "x", "emoji": "phone"}')!.emoji, isNull);
    expect(Reminder.tryParse('{"summary": "x", "emoji": 5}')!.emoji, isNull);
  });

  test('copies keep the emoji', () {
    final r = Reminder.tryParse('{"summary": "Water plants", "emoji": "🌱"}')!;
    expect(r.withList('Home').emoji, '🌱');
    expect(r.withCategory('home').emoji, '🌱');
    expect(r.withEmoji('💧').emoji, '💧');
  });

  test('parses a start and end', () {
    final r = Reminder.tryParse('{"summary": "Meeting", "from": "2026-11-17T14:00:00", "to": "2026-11-17T15:00:00"}')!;
    expect(r.from, DateTime(2026, 11, 17, 14));
    expect(r.to, DateTime(2026, 11, 17, 15));
    expect(r.triggerType, 'time');
    expect(r.withList('Work').to, r.to);
    expect(r.withCategory('work').to, r.to);
    expect(r.withEmoji('📅').to, r.to);
  });

  test('still reads the old "when" as the start', () {
    final r = Reminder.tryParse('{"summary": "Call mom", "when": "2026-11-17T18:00:00"}')!;
    expect(r.from, DateTime(2026, 11, 17, 18));
    expect(r.to, isNull);
  });

  test('drops an end that is not after the start, or has no start', () {
    expect(Reminder.tryParse('{"summary": "x", "from": "2026-11-17T15:00:00", "to": "2026-11-17T14:00:00"}')!.to, isNull);
    expect(Reminder.tryParse('{"summary": "x", "to": "2026-11-17T14:00:00"}')!.to, isNull);
  });

  test('an activity clears the start and end', () {
    final r = Reminder.tryParse(
      '{"summary": "x", "activity": "WALKING", "from": "2026-11-17T14:00:00", "to": "2026-11-17T15:00:00"}',
    )!;
    expect(r.from, isNull);
    expect(r.to, isNull);
  });
}
