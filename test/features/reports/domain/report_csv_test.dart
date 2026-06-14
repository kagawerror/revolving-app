import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/reports/domain/report_csv.dart';
import 'package:rev_app/features/reports/domain/report_models.dart';
import 'package:rev_app/features/reports/domain/report_period.dart';

void main() {
  test('replenishmentDetailCsv: header, full/partial rows, grand total', () {
    final summary = ReportSummary<ReplenishedLineRow>(
      rows: [
        ReplenishedLineRow(
          approvedDate: DateTime(2026, 6, 10), fundName: 'AUDIT',
          beneficiaryName: 'Alice', purpose: 'Laptop',
          amount: Money.fromCentavos(5000000), isPartial: false,
          remarks: '', replenishmentId: 'rep1',
        ),
        ReplenishedLineRow(
          approvedDate: DateTime(2026, 6, 10), fundName: 'AUDIT',
          beneficiaryName: 'Bob', purpose: 'Load, urgent',
          amount: Money.fromCentavos(40000), isPartial: true,
          remarks: 'first', replenishmentId: 'rep1',
        ),
      ],
      grandTotal: Money.fromCentavos(5040000),
      period: ReportPeriod(granularity: PeriodGranularity.month, anchor: DateTime(2026, 6, 1)),
    );

    final csv = replenishmentDetailCsv(summary, 'June 2026');
    final lines = csv.trim().split('\n');
    expect(lines.first, 'Approved date,Fund,Beneficiary,Purpose,Type,Amount');
    expect(lines[1], '2026-06-10,AUDIT,Alice,Laptop,Full,50000.00');
    expect(lines[2], '2026-06-10,AUDIT,Bob,"Load, urgent",Partial,400.00');
    expect(lines.last, 'GRAND TOTAL (June 2026),,,,,50400.00');
  });
}
