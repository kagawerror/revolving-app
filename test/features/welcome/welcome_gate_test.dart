import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/welcome/presentation/welcome_gate.dart';

void main() {
  // A child stands in for the routed app beneath the gate.
  const appChild = Text('APP', textDirection: TextDirection.ltr);

  Widget buildGate() {
    return const ProviderScope(
      child: MaterialApp(
        home: WelcomeGate(child: appChild),
      ),
    );
  }

  testWidgets('shows the welcome on top of the routed app first', (
    tester,
  ) async {
    await tester.pumpWidget(buildGate());
    await tester.pump();

    // Welcome is visible (greeting + primary button present).
    expect(find.text("Let's Go"), findsOneWidget);
    expect(find.textContaining('Revvy'), findsOneWidget);
    // The app child is mounted beneath the welcome (initializing).
    expect(find.text('APP'), findsOneWidget);
  });

  testWidgets('does not self-dismiss — stays until the user acts', (
    tester,
  ) async {
    await tester.pumpWidget(buildGate());
    await tester.pump();

    expect(find.text("Let's Go"), findsOneWidget);

    // Let plenty of time pass; there is no auto-dismiss timer, so the welcome
    // must still be on screen.
    await tester.pump(const Duration(minutes: 10));
    await tester.pumpAndSettle();

    expect(find.text("Let's Go"), findsOneWidget);
    expect(find.textContaining('Revvy'), findsOneWidget);
  });

  testWidgets('tapping Let\'s Go dismisses the welcome', (tester) async {
    await tester.pumpWidget(buildGate());
    await tester.pump();

    await tester.tap(find.text("Let's Go"));
    await tester.pumpAndSettle();

    expect(find.text("Let's Go"), findsNothing);
    expect(find.textContaining('Revvy'), findsNothing);
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
            home: WelcomeGate(child: appChild),
          ),
        );

    await tester.pumpWidget(gate());
    await tester.pump();
    await tester.tap(find.text("Let's Go"));
    await tester.pumpAndSettle();
    expect(find.text("Let's Go"), findsNothing);

    // Rebuild the whole tree against the same provider container.
    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();

    // The welcome must NOT re-appear; the app stays visible.
    expect(find.text("Let's Go"), findsNothing);
    expect(find.textContaining('Revvy'), findsNothing);
    expect(find.text('APP'), findsOneWidget);
  });
}
