import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nagadai/widgets/reminder_composer.dart';

void main() {
  final now = DateTime(2026, 11, 16, 10);

  Future<String> format(WidgetTester tester, DateTime from, DateTime? to) async {
    late String out;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        out = formatReminderRange(context, from, to, now: now);
        return const SizedBox.shrink();
      }),
    ));
    return out;
  }

  testWidgets('a single start', (tester) async {
    expect(await format(tester, DateTime(2026, 11, 17, 18), null), 'Tomorrow at 6:00 PM');
  });

  testWidgets('same day shows the end time only', (tester) async {
    expect(await format(tester, DateTime(2026, 11, 16, 14), DateTime(2026, 11, 16, 15)), 'Today at 2:00 PM – 3:00 PM');
  });

  testWidgets('different days show both days', (tester) async {
    expect(
      await format(tester, DateTime(2026, 11, 17, 9), DateTime(2026, 11, 20, 18)),
      'Tomorrow at 9:00 AM – Fri, Nov 20 at 6:00 PM',
    );
  });
}
