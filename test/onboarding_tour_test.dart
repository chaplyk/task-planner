import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nagadai/widgets/onboarding_tour.dart';

void main() {
  Future<void> pumpTour(WidgetTester tester, {List<int>? pages, List<int>? skips}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          // Nothing plays by itself then, so pumpAndSettle can settle.
          data: const MediaQueryData(size: Size(400, 860), disableAnimations: true),
          child: OnboardingTour(
            signInActions: const Text('SIGN IN ACTIONS'),
            onPage: pages?.add,
            onSkip: skips?.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Next plays every kind of reminder before sign in', (tester) async {
    final pages = <int>[];
    await pumpTour(tester, pages: pages);

    for (final (_, title, _) in tourTypes) {
      expect(find.text(title), findsOneWidget, reason: title);
      expect(find.text('SIGN IN ACTIONS'), findsNothing);
      expect(find.text('Swipe to continue'), findsOneWidget);
      await tester.fling(find.text(title), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
    }
    expect(find.text('SIGN IN ACTIONS'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    expect(pages, [for (var i = 1; i <= tourTypes.length; i++) i]);
  });

  testWidgets('Skip jumps to sign in, and Watch again starts over', (tester) async {
    final skips = <int>[];
    await pumpTour(tester, skips: skips);
    await tester.tap(find.text('Swipe to continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('SIGN IN ACTIONS'), findsOneWidget);
    expect(skips, [1]);

    await tester.tap(find.text('Watch again'));
    await tester.pumpAndSettle();
    expect(find.text(tourTypes.first.$2), findsOneWidget);
  });

  testWidgets('stories move on by themselves', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 860)),
          child: OnboardingTour(signInActions: const Text('SIGN IN ACTIONS')),
        ),
      ),
    );
    for (var i = 0; i < tourTypes.length; i++) {
      await tester.pump(const Duration(milliseconds: 5300));
    }
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('SIGN IN ACTIONS'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
