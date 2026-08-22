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
    // Row 2: the column header (row 1 is the spacer). The Fund column is
    // dropped from the per-row detail, so Requestor now sits at index 1.
    expect((rows[2][0]?.value as TextCellValue).value.text, 'Approved date');
    expect((rows[2][1]?.value as TextCellValue).value.text, 'Requestor');
  });

  test('replenishmentDetailXlsx: fund banners A->Z, GRAND TOTAL last row', () {
    ReplenishedLineRow line(String fund, int cents) => ReplenishedLineRow(
          approvedDate: DateTime(2026, 6, 10), fundName: fund,
          beneficiaryName: 'n', purpose: 'p',
          amount: Money.fromCentavos(cents), isPartial: false,
          remarks: '', replenishmentId: 'rep1',
        );
    final summary = ReportSummary<ReplenishedLineRow>(
      rows: [line('Zulu', 100), line('Alpha', 200)],
      grandTotal: Money.fromCentavos(300),
      period: ReportPeriod(
          granularity: PeriodGranularity.month, anchor: DateTime(2026, 6, 1)),
    );
    final bytes = replenishmentDetailXlsx(summary, 'June 2026', '');
    final rows = Excel.decodeBytes(bytes).tables['Replenishment detail']!.rows;

    String? text(List<Data?> r) =>
        r.isEmpty ? null : (r.first?.value as TextCellValue?)?.value.text;

    final banners = <String>[];
    for (final r in rows) {
      if (text(r) == 'Fund') {
        banners.add((r[1]?.value as TextCellValue).value.text ?? '');
      }
    }
    expect(banners, ['Alpha', 'Zulu']);

    // The last non-empty row is the GRAND TOTAL.
    final lastWithText =
        rows.lastWhere((r) => text(r) != null && text(r)!.isNotEmpty);
    expect(text(lastWithText)!, startsWith('GRAND TOTAL'));
  });
}
