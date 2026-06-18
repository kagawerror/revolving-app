import '../../../core/error/result.dart';
import 'report_models.dart';

/// File format the user can export a report as. Drives the chooser sheet, the
/// confirm dialog's "Format" row, and which bytes/extension/MIME the share
/// service produces.
enum ReportExportFormat { pdf, csv, excel }

/// Short, user-facing label + file extension for a format.
extension ReportExportFormatX on ReportExportFormat {
  String get label => switch (this) {
    ReportExportFormat.pdf => 'PDF',
    ReportExportFormat.csv => 'CSV',
    ReportExportFormat.excel => 'Excel',
  };

  /// File extension (no dot) the share service writes the temp file with.
  String get extension => switch (this) {
    ReportExportFormat.pdf => 'pdf',
    ReportExportFormat.csv => 'csv',
    ReportExportFormat.excel => 'xlsx',
  };
}

/// Which dataset is being exported.
enum ReportKind { released, replenishments }

/// Share-service surface the export action calls — one generic entry point for
/// all three formats. The screen hands over the chosen [format], the [kind], the
/// settled [summary], and the human [periodLabel]; the implementation builds the
/// bytes, writes a temp file, and shares it. Returns a [Result] so the screen
/// maps failures via the shared `failure_ui` extension. Keep amounts/PII out of
/// logs in the implementation.
///
/// `summary` is `ReportSummary<ReleasedRequestRow>` when `kind == released`,
/// else `ReportSummary<ReplenishmentRow>` — the screen guarantees the pairing.
abstract class ReportShareService {
  Future<Result<void>> shareReport(
    ReportExportFormat format,
    ReportKind kind,
    ReportSummary<Object> summary,
    String periodLabel,
    String companyName,
  );

  /// Export the DETAILED (per-request) replenishment report. Separate entry so
  /// [ReportKind] stays mapped 1:1 to the on-screen tabs.
  Future<Result<void>> shareReplenishmentDetail(
    ReportExportFormat format,
    ReportSummary<ReplenishedLineRow> summary,
    String periodLabel,
    String companyName,
  );
}
