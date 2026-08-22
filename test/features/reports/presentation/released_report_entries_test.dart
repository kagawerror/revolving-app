import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/reports/domain/report_models.dart';
import 'package:rev_app/features/reports/presentation/released_report_body.dart';

/// The on-screen released tab flattens fund groups into a [ReportEntry] list so
/// the flutter_animate stagger applies per visual row. These pin the flattening:
/// header → rows (oldest-first) → subtotal, funds A->Z, subtotals reconciling to
/// the grand total.
void main() {
  ReleasedRequestRow row(
    String fund,
    int cents,
    DateTime date, {
    String who = 'n',
  }) =>
      ReleasedRequestRow(
        requestId: '$fund-$who-$cents',
        beneficiaryName: who,
        purpose: 'p',
        amount: Money.fromCentavos(cents),
        effectiveDate: date,
        datePending: false,
        fundName: fund,
      );

  test('empty rows yield no entries', () {
    expect(buildReleasedEntries(const []), isEmpty);
  });

  test('one group: header, row, subtotal in order', () {
    final entries = buildReleasedEntries([row('Petty Cash', 500, DateTime(2026, 6, 1))]);
    expect(entries.length, 3);
    expect(entries[0], isA<FundHeaderEntry>());
    expect((entries[0] as FundHeaderEntry).fundName, 'Petty Cash');
    expect(entries[1], isA<ReleasedRowEntry>());
    expect(entries[2], isA<FundSubtotalEntry>());
    expect((entries[2] as FundSubtotalEntry).amount.centavos, 500);
  });

  test('multiple funds: groups A->Z, rows oldest-first, subtotals reconcile', () {
    final entries = buildReleasedEntries([
      row('Zulu', 100, DateTime(2026, 6, 5)),
      row('Alpha', 200, DateTime(2026, 6, 20), who: 'late'),
      row('Alpha', 300, DateTime(2026, 6, 2), who: 'early'),
    ]);

    // Header order is A->Z.
    final headers = entries
        .whereType<FundHeaderEntry>()
        .map((e) => e.fundName)
        .toList();
    expect(headers, ['Alpha', 'Zulu']);

    // Within Alpha, the oldest row comes first.
    final firstAlphaRow =
        entries.whereType<ReleasedRowEntry>().first.row;
    expect(firstAlphaRow.beneficiaryName, 'early');

    // Subtotals reconcile to the overall grand total.
    final subtotalSum = entries
        .whereType<FundSubtotalEntry>()
        .fold<int>(0, (a, e) => a + e.amount.centavos);
    expect(subtotalSum, 600);
  });

  test('blank fund name groups under Unassigned', () {
    final entries = buildReleasedEntries([row('   ', 100, DateTime(2026, 6, 1))]);
    expect((entries.first as FundHeaderEntry).fundName, 'Unassigned');
  });
}
