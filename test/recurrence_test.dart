import 'package:flutter_test/flutter_test.dart';
import 'package:nagadai/models/recurrence.dart';

void main() {
  group('advance', () {
    final from = DateTime(2026, 11, 16, 10, 30);

    test('hours, days, weeks', () {
      expect(const Recurrence(every: 3, unit: 'hour').advance(from), DateTime(2026, 11, 16, 13, 30));
      expect(const Recurrence(every: 2, unit: 'day').advance(from), DateTime(2026, 11, 18, 10, 30));
      expect(const Recurrence(every: 2, unit: 'week').advance(from), DateTime(2026, 11, 30, 10, 30));
    });

    test('months clamp to the end of a shorter month', () {
      const monthly = Recurrence(every: 1, unit: 'month');
      expect(monthly.advance(DateTime(2027, 1, 31, 9)), DateTime(2027, 2, 28, 9));
      expect(monthly.advance(DateTime(2026, 12, 15)), DateTime(2027, 1, 15));
    });

    test('a day keeps the time of day across a daylight-saving change', () {
      // In zones with DST one of these days is 23 or 25 hours long; the wall time must not move.
      final next = const Recurrence(every: 1, unit: 'day').advance(DateTime(2027, 3, 27, 9));
      expect((next.day, next.hour, next.minute), (28, 9, 0));
    });
  });

  group('nextDueAfterDone', () {
    final due = DateTime(2026, 11, 16, 9);

    test('after-I-finish counts from completion', () {
      const r = Recurrence(every: 3, unit: 'day');
      expect(r.nextDueAfterDone(prevDue: due, doneAt: DateTime(2026, 11, 17, 20)), DateTime(2026, 11, 20, 20));
    });

    test('fixed keeps the rhythm when done late', () {
      const r = Recurrence(every: 1, unit: 'week', mode: Recurrence.modeFixed);
      expect(r.nextDueAfterDone(prevDue: due, doneAt: DateTime(2026, 11, 18, 12)), DateTime(2026, 11, 23, 9));
    });

    test('fixed skips several missed cycles', () {
      const r = Recurrence(every: 1, unit: 'day', mode: Recurrence.modeFixed);
      expect(r.nextDueAfterDone(prevDue: due, doneAt: DateTime(2026, 11, 20, 12)), DateTime(2026, 11, 21, 9));
    });

    test('fixed done early still moves one cycle', () {
      const r = Recurrence(every: 1, unit: 'day', mode: Recurrence.modeFixed);
      expect(r.nextDueAfterDone(prevDue: due, doneAt: DateTime(2026, 11, 16, 7)), DateTime(2026, 11, 17, 9));
    });
  });

  test('tryParse validates model output', () {
    expect(Recurrence.tryParse({'every': 2, 'unit': 'week'}), const Recurrence(every: 2, unit: 'week'));
    expect(Recurrence.tryParse({'every': 1.0, 'unit': 'day'}), const Recurrence(every: 1, unit: 'day'));
    expect(Recurrence.tryParse({'unit': 'month'}), const Recurrence(every: 1, unit: 'month'));
    expect(Recurrence.tryParse({'every': 2, 'unit': 'year'}), isNull);
    expect(Recurrence.tryParse({'every': 0, 'unit': 'day'}), isNull);
    expect(Recurrence.tryParse({'every': 1.5, 'unit': 'day'}), isNull);
    expect(Recurrence.tryParse('daily'), isNull);
  });

  test('label', () {
    expect(const Recurrence(every: 1, unit: 'day').label, 'Every day');
    expect(const Recurrence(every: 2, unit: 'week').label, 'Every 2 weeks');
  });

  test('remainingShare', () {
    final start = DateTime(2026, 11, 16);
    final due = DateTime(2026, 11, 18);
    expect(remainingShare(start, start, due), 1);
    expect(remainingShare(DateTime(2026, 11, 17), start, due), 0.5);
    expect(remainingShare(DateTime(2026, 11, 19), start, due), 0);
  });

  test('dueLabel', () {
    final now = DateTime(2026, 11, 16, 10);
    expect(dueLabel(now, DateTime(2026, 11, 20, 10)), 'due in 4 days');
    expect(dueLabel(now, DateTime(2026, 11, 17, 10)), 'due in 1 day');
    expect(dueLabel(now, DateTime(2026, 11, 16, 13)), 'due in 3 h');
    expect(dueLabel(now, DateTime(2026, 11, 16, 10, 20)), 'due in 20 min');
    expect(dueLabel(now, now), 'due now');
    expect(dueLabel(now, DateTime(2026, 11, 14, 9)), 'overdue 2 days');
  });
}
