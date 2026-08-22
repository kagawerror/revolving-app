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

    final csv = replenishmentDetailCsv(summary, 'June 2026', '');
    final lines = csv.trim().split('\n');
    // Fund column is dropped from the per-row detail; the fund name is now a
    // banner heading above its group, with a per-fund subtotal below.
    expect(lines.first, 'Approved date,Requestor,Purpose,Type,Amount');
    expect(lines[1], 'Fund,AUDIT');
    expect(lines[2], '2026-06-10,Alice,Laptop,Full,50000.00');
    expect(lines[3], '2026-06-10,Bob,"Load, urgent",Partial,400.00');
    expect(lines[4], 'Subtotal,,,,50400.00');
    expect(lines.last, 'GRAND TOTAL (June 2026),,,,50400.00');
  });

  test('replenishmentDetailCsv: company header line when name provided', () {
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

    final csv = replenishmentDetailCsv(summary, 'June 2026', 'Acme Corp');
    final lines = csv.split('\n');
    expect(lines.first, 'Company,Acme Corp');
    expect(lines[1], '');
    expect(lines[2], 'Approved date,Requestor,Purpose,Type,Amount');
  });

  test('replenishmentDetailCsv: multiple funds banner A->Z, grand total last',
      () {
    ReplenishedLineRow line(String fund, String who, int cents) =>
        ReplenishedLineRow(
          approvedDate: DateTime(2026, 6, 10), fundName: fund,
          beneficiaryName: who, purpose: 'p',
          amount: Money.fromCentavos(cents), isPartial: false,
          remarks: '', replenishmentId: 'rep1',
        );
    final summary = ReportSummary<ReplenishedLineRow>(
      rows: [
        line('Zulu', 'Z', 100),
        line('Alpha', 'A', 200),
      ],
      grandTotal: Money.fromCentavos(300),
      period: ReportPeriod(
          granularity: PeriodGranularity.month, anchor: DateTime(2026, 6, 1)),
    );
    final lines = replenishmentDetailCsv(summary, 'June 2026', '').trim().split('\n');
    final banners =
        lines.where((l) => l.startsWith('Fund,')).map((l) => l).toList();
    // Funds appear A->Z.
    expect(banners, ['Fund,Alpha', 'Fund,Zulu']);
    // Grand total is still the last line (300 centavos == 3.00 pesos).
    expect(lines.last, 'GRAND TOTAL (June 2026),,,,3.00');
    // Per-fund subtotals reconcile to the grand total: 2.00 + 1.00 == 3.00.
    final subtotals = lines
        .where((l) => l.startsWith('Subtotal,'))
        .map((l) => l.split(',').last)
        .toList();
    expect(subtotals, ['2.00', '1.00']);
  });
}
