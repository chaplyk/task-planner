import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nagadai/recurring_repo.dart';
import 'package:nagadai/widgets/routine_card.dart';

void main() {
  final now = DateTime(2026, 11, 17, 12);
  final routine = Routine('1000000001', {
    'name': 'Water plants',
    'emoji': '🌱',
    'every': 2,
    'unit': 'day',
    'nextDue': Timestamp.fromDate(now.add(const Duration(days: 1))),
    'periodStart': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
  });

  Future<(List<String>,)> pump(WidgetTester tester) async {
    final events = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 180,
            height: 230,
            child: RoutineCard(
              routine: routine,
              now: now,
              onDone: () => events.add('done'),
              onAction: (a) => events.add(a.name),
            ),
          ),
        ),
      ),
    ));
    return (events,);
  }

  testWidgets('a short tap opens the routine instead of finishing it', (tester) async {
    final (events,) = await pump(tester);
    await tester.tap(find.text('Water plants'));
    await tester.pumpAndSettle();
    expect(events, ['edit']);
  });

  testWidgets('holding marks it done, and letting go afterwards is not a tap', (tester) async {
    final (events,) = await pump(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.text('Water plants')));
    // The press registers after the 100 ms tap timeout; the ring starts filling on the next frame.
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Hold to finish…'), findsOneWidget);
    expect(events, isEmpty);
    await tester.pump(const Duration(milliseconds: 700));
    expect(events, ['done']);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(events, ['done']);
  });

  testWidgets('letting go early cancels', (tester) async {
    final (events,) = await pump(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.text('Water plants')));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(0, 200)); // slides off: not a tap either
    await gesture.up();
    await tester.pumpAndSettle();
    expect(events, isNot(contains('done')));
  });

  testWidgets('the menu offers Mark as done', (tester) async {
    final (events,) = await pump(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as done'));
    await tester.pumpAndSettle();
    expect(events, ['done']);
  });
}
