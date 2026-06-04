import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/welcome/presentation/welcome_gate.dart';

void main() {
  // A child stands in for the routed app beneath the gate.
  const appChild = Text('APP', textDirection: TextDirection.ltr);

  Widget buildGate({required Duration autoDismissAfter}) {
    return ProviderScope(
      child: MaterialApp(
        home: WelcomeGate(
          autoDismissAfter: autoDismissAfter,
          child: appChild,
        ),
      ),
    );
  }

  testWidgets('shows the welcome on top of the routed app first', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildGate(autoDismissAfter: const Duration(minutes: 5)),
    );
    await tester.pump();

    // Welcome is visible (greeting + primary button present).
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.textContaining('Revvy'), findsOneWidget);
    // The app child is mounted beneath the welcome (initializing).
    expect(find.text('APP'), findsOneWidget);
  });

  testWidgets('tapping Get Started dismisses the welcome', (tester) async {
    await tester.pumpWidget(
      buildGate(autoDismissAfter: const Duration(minutes: 5)),
    );
    await tester.pump();

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(find.text('Get Started'), findsNothing);
    expect(find.textContaining('Revvy'), findsNothing);
    expect(find.text('APP'), findsOneWidget);
  });

  testWidgets('auto-dismisses after the configured delay', (tester) async {
    await tester.pumpWidget(
      buildGate(autoDismissAfter: const Duration(milliseconds: 10)),
    );
    await tester.pump();

    // Welcome present before the timer fires.
    expect(find.text('Get Started'), findsOneWidget);

    // Advance past the auto-dismiss delay and let the fade settle.
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(find.text('Get Started'), findsNothing);
    expect(find.text('APP'), findsOneWidget);
  });

  testWidgets('stays dismissed across a rebuild (router builder re-run)', (
    tester,
  ) async {
    // A shared container so the in-memory dismiss flag survives a fresh widget
    // tree — this models MaterialApp.router's `builder` re-running on a router
    // notify, which recreates the WelcomeGate widget at a stable position.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    Widget gate() => UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: WelcomeGate(
              autoDismissAfter: Duration(minutes: 5),
              child: appChild,
            ),
          ),
        );

    await tester.pumpWidget(gate());
    await tester.pump();
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.text('Get Started'), findsNothing);

    // Rebuild the whole tree against the same provider container.
    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();

    // The welcome must NOT re-appear; the app stays visible.
    expect(find.text('Get Started'), findsNothing);
    expect(find.textContaining('Revvy'), findsNothing);
    expect(find.text('APP'), findsOneWidget);
  });
}
