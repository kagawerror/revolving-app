import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/money/money.dart';
import 'report_models.dart';

/// PDF-safe peso amount. The embedded Helvetica/standard PDF fonts can't draw
/// the `₱` glyph (U+20B1), so the human-facing PDF uses the ASCII "PHP " prefix
/// with grouped thousands and two decimals, e.g. `PHP 1,234.50`. (CSV/Excel use
/// bare numeric pesos; on-screen + snackbars use `Money.format()` with `₱`.)
String _pdfPeso(Money m) =>
    NumberFormat('#,##0.00', 'en_PH').format(m.centavos / 100);

/// Print-ready PDF for the released-requests report: a title, the period label,
/// a name/purpose/date/amount table, and a bold GRAND TOTAL row. Amounts use
/// the human peso format (₱) since the PDF is human-facing. Async because
/// `Document.save()` is.
Future<Uint8List> releasedReportPdf(
  ReportSummary<ReleasedRequestRow> summary,
  String periodLabel,
) async {
  final doc = pw.Document();
  final dateFmt = DateFormat('MMM d, yyyy');

  final dataRows = <List<String>>[
    for (final r in summary.rows)
      [
        r.beneficiaryName,
        r.purpose,
        '${dateFmt.format(r.effectiveDate)}${r.datePending ? ' (pending)' : ''}',
        'PHP ${_pdfPeso(r.amount)}',
      ],
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        _header('Released Requests', periodLabel, summary.rows.length),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: const ['Beneficiary', 'Purpose', 'Date', 'Amount'],
          data: dataRows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignments: const {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerRight,
          },
        ),
        pw.SizedBox(height: 12),
        _grandTotal('PHP ${_pdfPeso(summary.grandTotal)}'),
      ],
    ),
  );

  return doc.save();
}

/// Print-ready PDF for the replenishments report.
Future<Uint8List> replenishmentReportPdf(
  ReportSummary<ReplenishmentRow> summary,
  String periodLabel,
) async {
  final doc = pw.Document();
  final dateFmt = DateFormat('MMM d, yyyy');

  final dataRows = <List<String>>[
    for (final r in summary.rows)
      [
        () {
          final d = r.approvedDate ?? r.createdDate;
          return d == null ? '—' : dateFmt.format(d);
        }(),
        '${r.itemCount}',
        'PHP ${_pdfPeso(r.total)}',
      ],
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        _header('Replenishments', periodLabel, summary.rows.length),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: const ['Approved date', 'Requests', 'Total'],
          data: dataRows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignments: const {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
          },
        ),
        pw.SizedBox(height: 12),
        _grandTotal('PHP ${_pdfPeso(summary.grandTotal)}'),
      ],
    ),
  );

  return doc.save();
}

/// Print-ready PDF for the DETAILED replenishment report: a per-request table
/// (date/fund/beneficiary/purpose/type/amount) + a bold GRAND TOTAL row.
Future<Uint8List> replenishmentDetailPdf(
  ReportSummary<ReplenishedLineRow> summary,
  String periodLabel,
) async {
  final doc = pw.Document();
  final dateFmt = DateFormat('MMM d, yyyy');

  final dataRows = <List<String>>[
    for (final r in summary.rows)
      [
        r.approvedDate == null ? '—' : dateFmt.format(r.approvedDate!),
        r.fundName,
        r.beneficiaryName,
        r.purpose,
        r.isPartial ? 'Partial' : 'Full',
        'PHP ${_pdfPeso(r.amount)}',
      ],
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        _header('Replenishment detail', periodLabel, summary.rows.length),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: const [
            'Approved date',
            'Fund',
            'Beneficiary',
            'Purpose',
            'Type',
            'Amount',
          ],
          data: dataRows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignments: const {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerLeft,
            4: pw.Alignment.centerLeft,
            5: pw.Alignment.centerRight,
          },
        ),
        pw.SizedBox(height: 12),
        _grandTotal('PHP ${_pdfPeso(summary.grandTotal)}'),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _header(String title, String periodLabel, int rowCount) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        periodLabel,
        style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
      ),
      pw.Text(
        rowCount == 1 ? '1 row' : '$rowCount rows',
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
      ),
    ],
  );
}

pw.Widget _grandTotal(String formattedTotal) {
  return pw.Container(
    alignment: pw.Alignment.centerRight,
    child: pw.Text(
      'GRAND TOTAL   $formattedTotal',
      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
    ),
  );
}
