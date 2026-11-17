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
    expect(r.when, isNull);
  });

  test('no summary or broken JSON gives null', () {
    expect(Reminder.tryParse('{"summary": 5}'), isNull);
    expect(Reminder.tryParse('{"summary": "x", }'), isNull);
    expect(Reminder.tryParse('sorry'), isNull);
  });

  test('parses a repeat and keeps the first due time', () {
    final r = Reminder.tryParse('{"summary": "Water plants", "repeat": {"every": 3, "unit": "day"}, "when": "2026-11-17T09:00:00"}')!;
    expect(r.repeat, const Recurrence(every: 3, unit: 'day'));
    expect(r.when, DateTime(2026, 11, 17, 9));
    expect(r.triggerType, 'repeat');
  });

  test('drops an invalid repeat', () {
    expect(Reminder.tryParse('{"summary": "x", "repeat": {"every": 2, "unit": "year"}}')!.repeat, isNull);
    expect(Reminder.tryParse('{"summary": "x", "repeat": "daily"}')!.repeat, isNull);
    expect(Reminder.tryParse('{"summary": "x", "repeat": null}')!.triggerType, 'none');
  });
}
