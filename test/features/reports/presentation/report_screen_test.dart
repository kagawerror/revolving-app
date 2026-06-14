import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/reports/domain/report_export.dart';
import 'package:rev_app/features/reports/domain/report_models.dart';
import 'package:rev_app/features/reports/domain/report_period.dart';

class _FakeShare implements ReportShareService {
  ReportExportFormat? detailFormat;
  @override
  Future<Result<void>> shareReport(ReportExportFormat f, ReportKind k,
          ReportSummary<Object> s, String label) async =>
      const Ok(null);
  @override
  Future<Result<void>> shareReplenishmentDetail(ReportExportFormat f,
      ReportSummary<ReplenishedLineRow> s, String label) async {
    detailFormat = f;
    return const Ok(null);
  }
}

void main() {
  test('shareReplenishmentDetail records the chosen detail format', () async {
    final share = _FakeShare();
    final summary = ReportSummary<ReplenishedLineRow>(
      rows: const [],
      grandTotal: Money.zero,
      period: ReportPeriod(
          granularity: PeriodGranularity.month, anchor: DateTime(2026, 6, 1)),
    );
    final res = await share.shareReplenishmentDetail(
        ReportExportFormat.csv, summary, 'June 2026');
    expect(res.isOk, isTrue);
    expect(share.detailFormat, ReportExportFormat.csv);
  });
}
