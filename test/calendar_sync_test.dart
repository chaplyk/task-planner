import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagadai/calendar_sync.dart';

void main() {
  final start = DateTime(2026, 11, 18, 9);
  Map<String, dynamic> reminder({
    String triggerType = 'time',
    int status = 0,
    DateTime? from,
    DateTime? to,
    String summary = 'Call mom',
    String? emoji,
    bool legacyWhen = false,
  }) => {
    'summary': summary,
    'triggerType': triggerType,
    'status': status,
    legacyWhen ? 'when' : 'from': from == null ? null : Timestamp.fromDate(from),
    'to': to == null ? null : Timestamp.fromDate(to),
    'emoji': emoji,
  };

  test('a range keeps its start and end', () {
    final e = calendarEventFor(reminder(from: start, to: start.add(const Duration(hours: 2))))!;
    expect(e.start, start);
    expect(e.end, start.add(const Duration(hours: 2)));
  });

  test('without an end the event lasts 15 minutes', () {
    final e = calendarEventFor(reminder(from: start))!;
    expect(e.end, start.add(const Duration(minutes: 15)));
  });

  test('an end before the start is ignored', () {
    final e = calendarEventFor(reminder(from: start, to: start.subtract(const Duration(hours: 1))))!;
    expect(e.end, start.add(const Duration(minutes: 15)));
  });

  test('the title is the summary, without the emoji', () {
    expect(calendarEventFor(reminder(from: start, emoji: '📞'))!.title, 'Call mom');
  });

  test('documents saved before ranges existed use "when"', () {
    expect(calendarEventFor(reminder(from: start, legacyWhen: true))!.start, start);
  });

  test('only open time reminders belong in the calendar', () {
    expect(calendarEventFor(null), isNull);
    expect(calendarEventFor(reminder(from: start, triggerType: 'location')), isNull);
    expect(calendarEventFor(reminder(from: start, status: 1)), isNull);
    expect(calendarEventFor(reminder()), isNull); // no time
  });
}
