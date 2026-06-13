import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/error/failure.dart';
import '../../core/error/result.dart';
import '../../features/reports/domain/report_csv.dart';
import '../../features/reports/domain/report_export.dart';
import '../../features/reports/domain/report_models.dart';
import '../../features/reports/domain/report_pdf.dart';
import '../../features/reports/domain/report_xlsx.dart';

/// Builds the chosen export format from a settled [ReportSummary] and shares the
/// resulting temp file via the platform share sheet. Read-only with respect to
/// app state. Never logs file contents, amounts, or PII — only generic failure
/// markers.
class ReportShareServiceImpl implements ReportShareService {
  const ReportShareServiceImpl();

  @override
  Future<Result<void>> shareReport(
    ReportExportFormat format,
    ReportKind kind,
    ReportSummary<Object> summary,
    String periodLabel,
  ) async {
    try {
      final bytes = await _buildBytes(format, kind, summary, periodLabel);
      final filename =
          '${kind.name}_${_slug(periodLabel)}.${format.extension}';

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: _mime(format), name: filename)],
        ),
      );
      return const Ok(null);
    } catch (e, st) {
      // Never log the bytes/summary — only the failure marker.
      developer.log(
        'shareReport failed (${format.name}/${kind.name})',
        name: 'ReportShareService',
        error: e,
        stackTrace: st,
      );
      return const Err(
        UnexpectedFailure('Could not export the report. Please try again.'),
      );
    }
  }

  Future<Uint8List> _buildBytes(
    ReportExportFormat format,
    ReportKind kind,
    ReportSummary<Object> summary,
    String periodLabel,
  ) async {
    switch (kind) {
      case ReportKind.released:
        final s = ReportSummary<ReleasedRequestRow>(
          rows: summary.rows.cast<ReleasedRequestRow>(),
          grandTotal: summary.grandTotal,
          period: summary.period,
        );
        switch (format) {
          case ReportExportFormat.csv:
            return encodeCsvBytes(releasedReportCsv(s, periodLabel));
          case ReportExportFormat.excel:
            return releasedReportXlsx(s, periodLabel);
          case ReportExportFormat.pdf:
            return releasedReportPdf(s, periodLabel);
        }
      case ReportKind.replenishments:
        final s = ReportSummary<ReplenishmentRow>(
          rows: summary.rows.cast<ReplenishmentRow>(),
          grandTotal: summary.grandTotal,
          period: summary.period,
        );
        switch (format) {
          case ReportExportFormat.csv:
            return encodeCsvBytes(replenishmentReportCsv(s, periodLabel));
          case ReportExportFormat.excel:
            return replenishmentReportXlsx(s, periodLabel);
          case ReportExportFormat.pdf:
            return replenishmentReportPdf(s, periodLabel);
        }
    }
  }

  String _mime(ReportExportFormat f) => switch (f) {
        ReportExportFormat.pdf => 'application/pdf',
        ReportExportFormat.csv => 'text/csv',
        ReportExportFormat.excel =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      };
}

/// Encodes a CSV string to its on-disk bytes as UTF-8. Free-text fields
/// (beneficiary names, purposes) and the en-dash in week period labels are
/// non-ASCII, so each character may span multiple bytes — truncating UTF-16
/// code units to bytes would corrupt them.
Uint8List encodeCsvBytes(String csv) => Uint8List.fromList(utf8.encode(csv));

/// Lowercase, filesystem-safe slug for a period label: non-alphanumerics
/// collapse to single underscores, trimmed. e.g. "Jun 9–15, 2026" → "jun_9_15_2026".
String _slug(String label) {
  final lower = label.toLowerCase();
  final buf = StringBuffer();
  var lastUnderscore = false;
  for (final ch in lower.runes) {
    final isAlnum = (ch >= 0x30 && ch <= 0x39) || (ch >= 0x61 && ch <= 0x7a);
    if (isAlnum) {
      buf.writeCharCode(ch);
      lastUnderscore = false;
    } else if (!lastUnderscore) {
      buf.write('_');
      lastUnderscore = true;
    }
  }
  return buf.toString().replaceAll(RegExp(r'^_+|_+$'), '');
}
