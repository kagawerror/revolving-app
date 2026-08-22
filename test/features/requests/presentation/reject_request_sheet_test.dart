import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/core/validation/rejection_remarks.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/widgets/reject_request_sheet.dart';

/// The reject sheet is the confirmation step for cancelling a not-yet-released
/// request. Two things must hold: the reason gate can't be bypassed, and the
/// sheet must state plainly that no cash is deducted (the incharge's whole
/// worry when cancelling a mistaken request).
FundRequest _created() => FundRequest(
      id: 'r1',
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: 'Ben',
      amount: Money.fromCentavos(50000),
      purpose: 'Supplies',
      proofImageUrl: '',
      status: RequestStatus.created,
    );

void main() {
  /// Pumps a screen whose button opens the sheet, capturing what it returns.
  Future<void> pumpHost(WidgetTester tester, List<String?> captured) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async => captured
                    .add(await RejectRequestSheet.show(context, _created())),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('states that no cash will be deducted from the fund',
      (tester) async {
    await pumpHost(tester, <String?>[]);

    expect(
      find.textContaining('No cash', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('submit is disabled until the reason passes the shared rule',
      (tester) async {
    await pumpHost(tester, <String?>[]);

    final submit = find.widgetWithText(FilledButton, 'Reject request');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    // A too-short reason still fails the shared validator.
    await tester.enterText(find.byType(TextField), 'oops');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.enterText(
        find.byType(TextField), 'x' * kMinRejectionRemarksLength);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  });

  testWidgets('returns the trimmed reason on confirm', (tester) async {
    final captured = <String?>[];
    await pumpHost(tester, captured);

    await tester.enterText(
        find.byType(TextField), '   Duplicate of R-1042, created twice.   ');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reject request'));
    await tester.pumpAndSettle();

    expect(captured.single, 'Duplicate of R-1042, created twice.');
  });

  testWidgets('returns null when cancelled', (tester) async {
    final captured = <String?>[];
    await pumpHost(tester, captured);

    await tester.enterText(
        find.byType(TextField), 'Duplicate of R-1042, created twice.');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Keep request'));
    await tester.pumpAndSettle();

    expect(captured.single, isNull);
  });
}
