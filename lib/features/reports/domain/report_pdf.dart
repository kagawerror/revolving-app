import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/money/money.dart';
import 'report_math.dart';
import 'report_models.dart';

/// PDF-safe peso amount. The embedded Helvetica/standard PDF fonts can't draw
/// the `₱` glyph (U+20B1), so the human-facing PDF uses the ASCII "PHP " prefix
/// with grouped thousands and two decimals, e.g. `PHP 1,234.50`. (CSV/Excel use
/// bare numeric pesos; on-screen + snackbars use `Money.format()` with `₱`.)
String _pdfPeso(Money m) =>
    NumberFormat('#,##0.00', 'en_PH').format(m.centavos / 100);

/// Report brand colors. Deep "forest" green matches the app's default accent
/// (`app_accents.dart`); the tint is its light wash for the total chip. Reports
/// are static artifacts, so we use a fixed palette rather than the exporter's
/// live in-app accent — every export looks consistent regardless of who made it.
final _brand = PdfColor.fromInt(0xFF0B6E4F);
final _brandTint = PdfColor.fromInt(0xFFE8F1ED);

/// Print-ready PDF for the released-requests report: a title, the period label,
/// a name/purpose/date/amount table, and a bold GRAND TOTAL row. Amounts use
/// the human peso format (₱) since the PDF is human-facing. Async because
/// `Document.save()` is.
Future<Uint8List> releasedReportPdf(
  ReportSummary<ReleasedRequestRow> summary,
  String periodLabel,
  String companyName,
) async {
  final doc = pw.Document();
  final dateFmt = DateFormat('MMM d, yyyy');

  final groups = groupByFund<ReleasedRequestRow>(
    summary.rows,
    (r) => r.fundName,
    (r) => r.amount,
    (r) => r.datePending ? null : r.effectiveDate,
  );

  pw.Widget releasedTable(List<ReleasedRequestRow> rows) {
    final dataRows = <List<String>>[
      for (final r in rows)
        [
          r.beneficiaryName,
          r.purpose,
          '${dateFmt.format(r.effectiveDate)}${r.datePending ? ' (pending)' : ''}',
          'PHP ${_pdfPeso(r.amount)}',
        ],
    ];
    return pw.TableHelper.fromTextArray(
      headers: const ['Requestor', 'Purpose', 'Date', 'Amount'],
      data: dataRows,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignments: const {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerRight,
      },
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        _header(
          'Released Requests',
          periodLabel,
          summary.rows.length,
          companyName,
        ),
        pw.SizedBox(height: 12),
        for (final g in groups) ...[
          _fundHeading(g.fundName),
          releasedTable(g.rows),
          _subtotal(g.fundName, 'PHP ${_pdfPeso(g.subtotal)}'),
          pw.SizedBox(height: 14),
        ],
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
  String companyName,
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
        _header(
          'Replenishments',
          periodLabel,
          summary.rows.length,
          companyName,
        ),
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
  String companyName,
) async {
  final doc = pw.Document();
  final dateFmt = DateFormat('MMM d, yyyy');

  final groups = groupByFund<ReplenishedLineRow>(
    summary.rows,
    (r) => r.fundName,
    (r) => r.amount,
    (r) => r.approvedDate,
  );

  pw.Widget detailTable(List<ReplenishedLineRow> rows) {
    final dataRows = <List<String>>[
      for (final r in rows)
        [
          r.approvedDate == null ? '—' : dateFmt.format(r.approvedDate!),
          r.beneficiaryName,
          r.purpose,
          r.isPartial ? 'Partial' : 'Full',
          'PHP ${_pdfPeso(r.amount)}',
        ],
    ];
    return pw.TableHelper.fromTextArray(
      headers: const [
        'Approved date',
        'Requestor',
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
        4: pw.Alignment.centerRight,
      },
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        _header(
          'Replenishment detail',
          periodLabel,
          summary.rows.length,
          companyName,
        ),
        pw.SizedBox(height: 12),
        for (final g in groups) ...[
          _fundHeading(g.fundName),
          detailTable(g.rows),
          _subtotal(g.fundName, 'PHP ${_pdfPeso(g.subtotal)}'),
          pw.SizedBox(height: 14),
        ],
        _grandTotal('PHP ${_pdfPeso(summary.grandTotal)}'),
      ],
    ),
  );

  return doc.save();
}

/// Branded report masthead: the company name as the lead line (or the report
/// title itself when no company resolved), the report title as an uppercase
/// subtitle, a right-aligned period + row-count meta block, and a brand rule
/// underlining the whole band.
pw.Widget _header(
  String title,
  String periodLabel,
  int rowCount,
  String companyName,
) {
  final hasCompany = companyName.isNotEmpty;
  final rowsLabel = rowCount == 1 ? '1 row' : '$rowCount rows';
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  hasCompany ? companyName : title,
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: _brand,
                  ),
                ),
                if (hasCompany) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    title.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.2,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                periodLabel,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey800,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                rowsLabel,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Container(height: 2, color: _brand),
    ],
  );
}

/// Section heading for a per-fund group: a tinted band with a brand left rule
/// and the fund's name, introducing the detail table that follows.
pw.Widget _fundHeading(String fundName) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        // A non-uniform (left-only) border can't be combined with a
        // borderRadius in dart_pdf's painter, so the band is square with just
        // the brand left rule.
        decoration: pw.BoxDecoration(
          color: _brandTint,
          border: pw.Border(left: pw.BorderSide(color: _brand, width: 3)),
        ),
        child: pw.Text(
          fundName,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: _brand,
          ),
        ),
      ),
      pw.SizedBox(height: 6),
    ],
  );
}

/// Right-aligned per-fund subtotal line, set under the group's table with a thin
/// rule so each fund's running figure is legible before the GRAND TOTAL.
pw.Widget _subtotal(String fundName, String formatted) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
          ),
        ),
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(
              // ASCII hyphen, not an em-dash: the standard PDF Helvetica can't
              // draw U+2014 (same constraint that forces "PHP" over the peso
              // glyph), and it would render as a missing-glyph box.
              'Subtotal - $fundName',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Text(
              formatted,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: _brand,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Right-aligned GRAND TOTAL as a tinted, brand-bordered chip so the bottom-line
/// figure reads as the report's headline number.
pw.Widget _grandTotal(String formattedTotal) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: pw.BoxDecoration(
          color: _brandTint,
          borderRadius: pw.BorderRadius.circular(4),
          border: pw.Border.all(color: _brand, width: 0.5),
        ),
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(
              'GRAND TOTAL',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.0,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Text(
              formattedTotal,
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: _brand,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
