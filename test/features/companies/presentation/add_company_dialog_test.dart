import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/companies/presentation/add_company_dialog.dart';

void main() {
  testWidgets('Save is disabled when empty and enabled after a trimmed name',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showAddCompanyDialog(
                  context,
                  onSubmit: (_) async => true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    FilledButton saveButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));

    // Empty -> disabled.
    expect(saveButton().onPressed, isNull);

    // Whitespace only -> still disabled.
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(saveButton().onPressed, isNull);

    // Real name -> enabled.
    await tester.enterText(find.byType(TextField), '  Acme  ');
    await tester.pump();
    expect(saveButton().onPressed, isNotNull);
  });

  testWidgets('Save submits trimmed name and closes on success, returns name',
      (tester) async {
    final names = <String>[];
    String? returned;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  returned = await showAddCompanyDialog(
                    context,
                    onSubmit: (name) async {
                      names.add(name);
                      return true;
                    },
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  Acme Corp  ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(names, ['Acme Corp']);
    expect(returned, 'Acme Corp');
    expect(find.byType(TextField), findsNothing); // dialog closed
  });

  testWidgets('dialog stays open and Save re-enables when onSubmit returns false',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showAddCompanyDialog(
                  context,
                  onSubmit: (_) async => false,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Acme');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Still open.
    expect(find.byType(TextField), findsOneWidget);
    final save =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
    expect(save.onPressed, isNotNull);
  });

  testWidgets('Cancel closes the dialog and resolves to null', (tester) async {
    String? returned;
    var didResolve = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  returned = await showAddCompanyDialog(
                    context,
                    onSubmit: (_) async => true,
                  );
                  didResolve = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(didResolve, isTrue);
    expect(returned, isNull);
  });
}
