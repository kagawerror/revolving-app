import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/reports/domain/report_models.dart';
import 'package:rev_app/features/reports/domain/report_period.dart';
import 'package:rev_app/features/reports/domain/report_pdf.dart';

void main() {
  test('replenishmentDetailPdf: produces a non-empty PDF', () async {
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
    final bytes = await replenishmentDetailPdf(summary, 'June 2026', 'Acme Corp');
    expect(bytes, isNotEmpty);
    expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]); // "%PDF"
  });
}
