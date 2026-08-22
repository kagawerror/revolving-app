import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/replenishment/presentation/replenish_select_dialog.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/sync/presentation/sync_providers.dart';

Fund _fund() => Fund(
      id: 'f1',
      companyId: 'c1',
      name: 'Revolving Fund',
      originalBudget: Money.fromCentavos(10000000),
      availableBalance: Money.fromCentavos(200000),
      lowBalanceThresholdPct: 3,
      status: FundStatus.low,
    );

FundRequest _req(String id, int centavos) => FundRequest(
      id: id,
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'inc',
      beneficiaryName: 'Bene $id',
      amount: Money.fromCentavos(centavos),
      purpose: 'Purpose $id',
      proofImageUrl: 'http://img',
      status: RequestStatus.released,
    );

/// Hosts the dialog with connectivity pinned. The bare `connectivityProvider`
/// emits `false` (offline) in tests because there is no signed-in user, so
/// every form-validity test must explicitly run ONLINE to exercise the submit
/// gating it cares about. The offline path has its own test below.
Widget _host(List<FundRequest> releasable, {bool online = true}) =>
    ProviderScope(
      overrides: [
        connectivityProvider.overrideWith((ref) => Stream<bool>.value(online)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ReplenishSelectDialog(fund: _fund(), releasable: releasable),
        ),
      ),
    );

void main() {
  testWidgets('submit is disabled until a request is selected', (tester) async {
    await tester.pumpWidget(_host([_req('r1', 400000), _req('r2', 300000)]));
    final submit = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit & replenish'));
    expect(submit.onPressed, isNull); // disabled

    // Rows are tappable selection cards; tapping the beneficiary name toggles
    // selection via the row's InkWell.
    await tester.tap(find.text('Bene r1'));
    await tester.pump();

    final submit2 = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit & replenish'));
    expect(submit2.onPressed, isNotNull); // enabled
  });

  testWidgets('selected total reflects the checked requests', (tester) async {
    await tester.pumpWidget(_host([_req('r1', 400000), _req('r2', 300000)]));
    await tester.tap(find.text('Bene r1'));
    await tester.pump();
    expect(find.textContaining('₱4,000.00'), findsWidgets);
  });

  testWidgets('shows an empty state when nothing is releasable', (tester) async {
    await tester.pumpWidget(_host(const []));
    expect(find.text('Nothing to replenish'), findsOneWidget);
    expect(find.textContaining('Bene'), findsNothing); // no request cards
  });

  testWidgets('switching a row to Partial reveals amount + remarks and gates submit',
      (tester) async {
    await tester.pumpWidget(_host([_req('r1', 400000)]));
    await tester.tap(find.text('Bene r1'));
    await tester.pump();
    // Default Full -> submit enabled.
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit & replenish'))
            .onPressed,
        isNotNull);

    // Switch to Partial.
    await tester.tap(find.text('Partial'));
    await tester.pump();
    // Amount + remarks fields appear; submit disabled until valid.
    expect(find.widgetWithText(TextField, 'Partial amount'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Remarks'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit & replenish'))
            .onPressed,
        isNull);

    // Enter a valid partial (< 4000) + remarks -> enabled.
    await tester.enterText(
        find.widgetWithText(TextField, 'Partial amount'), '1000');
    await tester.enterText(find.widgetWithText(TextField, 'Remarks'), 'half');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit & replenish'))
            .onPressed,
        isNotNull);
  });

  testWidgets('deselecting a partial row clears it from the running total',
      (tester) async {
    await tester.pumpWidget(_host([_req('r1', 400000), _req('r2', 300000)]));
    // Select r1 and give it a partial amount of ₱1,000. (The amount alone drives
    // the running total; remarks only gate submit, so they're omitted here — a
    // second focused field would otherwise let the harness swallow the next tap.)
    await tester.tap(find.text('Bene r1'));
    await tester.pump();
    await tester.tap(find.text('Partial'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'Partial amount'), '1000');
    await tester.pump();
    expect(find.textContaining('₱1,000.00'), findsWidgets); // partial counted

    // Deselect r1: its partial amount must drop out of the total, and the
    // Full/Partial control must disappear with the card.
    await tester.tap(find.text('Bene r1'));
    await tester.pump();
    expect(find.textContaining('₱1,000.00'), findsNothing);
    expect(find.text('Partial'), findsNothing);

    // Submit is disabled again with nothing selected.
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit & replenish'))
            .onPressed,
        isNull);
  });

  testWidgets('offline gates submit and shows an offline notice', (tester) async {
    await tester.pumpWidget(
        _host([_req('r1', 400000), _req('r2', 300000)], online: false));
    // Select a request so the form would otherwise be valid/submittable.
    await tester.tap(find.text('Bene r1'));
    await tester.pump();

    // Even with a valid selection, being offline must keep submit disabled —
    // a replenishment can only be created against a live server, so a tap must
    // never hang on an unresolvable Firestore transaction.
    final submit = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit & replenish'));
    expect(submit.onPressed, isNull);

    // And the incharge is told WHY, rather than facing a dead button.
    expect(find.textContaining('offline'), findsWidgets);
  });

  testWidgets('a partial amount equal to or above remaining keeps submit disabled',
      (tester) async {
    await tester.pumpWidget(_host([_req('r1', 400000)]));
    await tester.tap(find.text('Bene r1'));
    await tester.pump();
    await tester.tap(find.text('Partial'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'Partial amount'), '4000'); // == remaining
    await tester.enterText(find.widgetWithText(TextField, 'Remarks'), 'all');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit & replenish'))
            .onPressed,
        isNull);
  });
}
