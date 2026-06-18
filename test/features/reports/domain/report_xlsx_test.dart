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
    final bytes = replenishmentDetailXlsx(summary, 'June 2026', '');
    expect(bytes, isNotEmpty);
    final book = Excel.decodeBytes(bytes);
    expect(book.tables.keys, contains('Replenishment detail'));

    // With no company name the FIRST row is the column header (Requestor, not
    // Beneficiary), i.e. no leading Company row.
    final firstRow = book.tables['Replenishment detail']!.rows.first;
    final firstCells =
        firstRow.map((c) => c?.value).whereType<TextCellValue>().toList();
    expect(firstCells.first.value.text, 'Approved date');
    expect(firstCells.map((c) => c.value.text), contains('Requestor'));
    expect(firstCells.map((c) => c.value.text), isNot(contains('Beneficiary')));
  });

  test('replenishmentDetailXlsx: company row + spacer precede the header', () {
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

    final bytes = replenishmentDetailXlsx(summary, 'June 2026', 'Acme Corp');
    final book = Excel.decodeBytes(bytes);
    final rows = book.tables['Replenishment detail']!.rows;

    // Row 0: ['Company', 'Acme Corp']
    expect((rows[0][0]?.value as TextCellValue).value.text, 'Company');
    expect((rows[0][1]?.value as TextCellValue).value.text, 'Acme Corp');
    // Row 2: the column header (row 1 is the spacer).
    expect((rows[2][0]?.value as TextCellValue).value.text, 'Approved date');
    expect((rows[2][2]?.value as TextCellValue).value.text, 'Requestor');
  });
}
