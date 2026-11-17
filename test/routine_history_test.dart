import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagadai/recurring_repo.dart';

void main() {
  Timestamp ts(DateTime d) => Timestamp.fromDate(d);

  test('history is newest first and tells late from on time', () {
    final r = Routine('1000000001', {
      'history': [
        {'at': ts(DateTime(2026, 11, 10, 9)), 'action': 'done', 'due': ts(DateTime(2026, 11, 10, 9))},
        {'at': ts(DateTime(2026, 11, 14, 20)), 'action': 'done', 'due': ts(DateTime(2026, 11, 12, 9))},
        {'at': ts(DateTime(2026, 11, 12, 8)), 'action': 'skip', 'due': ts(DateTime(2026, 11, 12, 9))},
      ],
    });
    expect(r.history.map((e) => e.at.day), [14, 12, 10]);
    expect(r.history[0].late, const Duration(days: 2, hours: 11));
    expect(r.history[1].skipped, isTrue);
    expect(r.history[2].late, isNull);
  });

  test('bad entries are ignored', () {
    final r = Routine('1000000001', {
      'history': [
        'done',
        {'action': 'done'},
        {'at': ts(DateTime(2026, 11, 10)), 'action': 'done'},
      ],
    });
    expect(r.history, hasLength(1));
    expect(r.history.single.due, isNull);
    expect(r.history.single.late, isNull);
  });

  test('a routine done before history existed shows its last completion', () {
    final r = Routine('1000000001', {'lastDone': ts(DateTime(2026, 11, 15, 18))});
    expect(r.history.single.at, DateTime(2026, 11, 15, 18));
    expect(r.history.single.skipped, isFalse);
  });
}
