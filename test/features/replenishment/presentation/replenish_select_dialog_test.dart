import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/replenishment/presentation/replenish_select_dialog.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

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

Widget _host(List<FundRequest> releasable) => ProviderScope(
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
        find.widgetWithText(FilledButton, 'Submit for approval'));
    expect(submit.onPressed, isNull); // disabled

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();

    final submit2 = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit for approval'));
    expect(submit2.onPressed, isNotNull); // enabled
  });

  testWidgets('selected total reflects the checked requests', (tester) async {
    await tester.pumpWidget(_host([_req('r1', 400000), _req('r2', 300000)]));
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.textContaining('₱4,000.00'), findsWidgets);
  });

  testWidgets('shows an empty state when nothing is releasable', (tester) async {
    await tester.pumpWidget(_host(const []));
    expect(find.text('No released requests to replenish.'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
  });
}
