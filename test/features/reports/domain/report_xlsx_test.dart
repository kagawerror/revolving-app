import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/reports/domain/report_models.dart';
import 'package:rev_app/features/reports/domain/report_period.dart';
import 'package:rev_app/features/reports/domain/report_xlsx.dart';

void main() {
  test('replenishmentDetailXlsx: non-empty workbook with a detail sheet', () {
    final summary = ReportSummary<ReplenishedLineRow>(
      rows: [
        ReplenishedLineRow(
          approvedDate: DateTime(2026, 6, 10), fundName: 'AUDIT',
          beneficiaryName: 'Alice', purpose: 'Laptop',
          amount: Money.fromCentavos(5000000), isPartial: false,
          remarks: '', replenishmentId: 'rep1',
        ),
      ],
      grandTotal: Money.fromCentavos(5000000),
      period: ReportPeriod(granularity: PeriodGranularity.month, anchor: DateTime(2026, 6, 1)),
    );
    final bytes = replenishmentDetailXlsx(summary, 'June 2026');
    expect(bytes, isNotEmpty);
    final book = Excel.decodeBytes(bytes);
    expect(book.tables.keys, contains('Replenishment detail'));
  });
}
