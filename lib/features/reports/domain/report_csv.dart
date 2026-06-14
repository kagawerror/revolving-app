import '../../../core/money/money.dart';
import 'report_models.dart';

/// Bare-pesos string for a [Money], e.g. `1234.50` — centavos/100 with exactly
/// two decimals, NO `₱`, NO thousands separators. Spreadsheets parse this as a
/// number; the human-facing PDF uses `Money.format()` instead.
String moneyPesosBare(Money m) {
  final cents = m.centavos;
  final whole = cents ~/ 100;
  final frac = (cents % 100).toString().padLeft(2, '0');
  return '$whole.$frac';
}

/// RFC-4180 field escaping. Quotes (and doubles inner quotes) when the field
/// contains a comma, quote, CR/LF, or has leading/trailing whitespace — beneficiary
/// names and purposes are free text and may contain any of these.
String csvField(String value) {
  final needsQuoting =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r') ||
      (value.isNotEmpty &&
          (value.trimLeft() != value || value.trimRight() != value));
  if (!needsQuoting) return value;
  return '"${value.replaceAll('"', '""')}"';
}

String _row(List<String> fields) => fields.map(csvField).join(',');

/// CSV for the released-requests report. Header + one row per release + a
/// trailing GRAND TOTAL line. Amounts are bare pesos. The period label and date
/// (ISO yyyy-MM-dd, with a `(pending)` marker for un-synced releases) make the
/// file self-describing.
String releasedReportCsv(
  ReportSummary<ReleasedRequestRow> summary,
  String periodLabel,
) {
  final b = StringBuffer();
  b.writeln(_row(['Beneficiary', 'Purpose', 'Date', 'Amount', 'Pending sync']));
  for (final r in summary.rows) {
    b.writeln(
      _row([
        r.beneficiaryName,
        r.purpose,
        _isoDate(r.effectiveDate),
        moneyPesosBare(r.amount),
        r.datePending ? 'yes' : 'no',
      ]),
    );
  }
  b.writeln(
    _row([
      'GRAND TOTAL',
      periodLabel,
      '',
      moneyPesosBare(summary.grandTotal),
      '',
    ]),
  );
  return b.toString();
}

/// CSV for the replenishments report. Header + one row per approved
/// replenishment + a trailing GRAND TOTAL line.
String replenishmentReportCsv(
  ReportSummary<ReplenishmentRow> summary,
  String periodLabel,
) {
  final b = StringBuffer();
  b.writeln(_row(['Approved date', 'Requests', 'Total']));
  for (final r in summary.rows) {
    final date = r.approvedDate ?? r.createdDate;
    b.writeln(
      _row([
        date == null ? '' : _isoDate(date),
        r.itemCount.toString(),
        moneyPesosBare(r.total),
      ]),
    );
  }
  b.writeln(
    _row([
      'GRAND TOTAL ($periodLabel)',
      '',
      moneyPesosBare(summary.grandTotal),
    ]),
  );
  return b.toString();
}

/// CSV for the DETAILED replenishment report: one row per replenished request
/// (full or partial installment) + a trailing GRAND TOTAL line. Amounts are
/// bare pesos so spreadsheets read them as numbers.
String replenishmentDetailCsv(
  ReportSummary<ReplenishedLineRow> summary,
  String periodLabel,
) {
  final b = StringBuffer();
  b.writeln(
    _row(['Approved date', 'Fund', 'Beneficiary', 'Purpose', 'Type', 'Amount']),
  );
  for (final r in summary.rows) {
    b.writeln(
      _row([
        r.approvedDate == null ? '' : _isoDate(r.approvedDate!),
        r.fundName,
        r.beneficiaryName,
        r.purpose,
        r.isPartial ? 'Partial' : 'Full',
        moneyPesosBare(r.amount),
      ]),
    );
  }
  b.writeln(
    _row([
      'GRAND TOTAL ($periodLabel)',
      '',
      '',
      '',
      '',
      moneyPesosBare(summary.grandTotal),
    ]),
  );
  return b.toString();
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
