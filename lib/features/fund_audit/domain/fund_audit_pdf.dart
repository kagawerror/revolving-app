import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'denomination.dart';
import 'fund_audit.dart';
import 'fund_audit_math.dart';

/// Formats centavos as an ASCII peso string, e.g. `PHP 1,234.56`. The bundled
/// Helvetica font cannot render the ₱ glyph, so certificates use `PHP`.
String _pdfPeso(int centavos) {
  final pesos = centavos / 100;
  return 'PHP ${NumberFormat('#,##0.00', 'en_US').format(pesos)}';
}

/// ASCII verdict label for the certificate (kept independent of the UI layer).
String _verdictLabel(AuditVerdict v) => switch (v) {
      AuditVerdict.shortage => 'SHORTAGE',
      AuditVerdict.overage => 'OVERAGE',
      AuditVerdict.balanced => 'BALANCED',
    };

/// Builds a one-page Proof-of-Cash certificate PDF for [audit].
///
/// The proof photo is fetched over the network and embedded; if the fetch fails
/// (offline, expired URL, missing) it degrades gracefully to a "proof on file"
/// note rather than failing the whole export. Amounts are ASCII `PHP`.
Future<Uint8List> fundAuditCertificatePdf(
  FundAudit audit, {
  http.Client? client,
}) async {
  final doc = pw.Document();

  final proofImage = await _fetchProofImage(audit.proofImageUrl, client);

  final dateText = audit.createdAt == null
      ? '--'
      : DateFormat('MMM d, y  h:mm a').format(audit.createdAt!.toLocal());

  // Sign convention: variance > 0 means cash is short.
  final variance = audit.varianceCentavos;
  final varianceText =
      '${variance > 0 ? '-' : variance < 0 ? '+' : ''}${_pdfPeso(variance.abs())}';

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Proof-of-Cash Certificate',
                style: pw.TextStyle(
                    fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(audit.companyName,
                style: const pw.TextStyle(fontSize: 12)),
            pw.Divider(),
            _row('Fund', audit.fundName),
            _row('Custodian', audit.custodianName),
            _row('Date counted', dateText),
            pw.SizedBox(height: 12),
            _row('Effective budget', _pdfPeso(audit.effectiveBudget.centavos)),
            _row('Outstanding released cash',
                _pdfPeso(audit.outstanding.centavos)),
            _row('Expected cash on hand',
                _pdfPeso(audit.effectiveBudget.centavos -
                    audit.outstanding.centavos)),
            _row('Physical cash counted', _pdfPeso(audit.physicalCash.centavos)),
            pw.SizedBox(height: 6),
            _row('Variance (${_verdictLabel(audit.verdict)})', varianceText,
                bold: true),
            pw.SizedBox(height: 16),
            pw.Text('Denomination breakdown',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            _denominationTable(audit),
            pw.SizedBox(height: 16),
            if (audit.note.isNotEmpty) ...[
              pw.Text('Note',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(audit.note),
              pw.SizedBox(height: 16),
            ],
            pw.Text('Proof of cash photo',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            if (proofImage != null)
              pw.Container(
                constraints: const pw.BoxConstraints(maxHeight: 240),
                child: pw.Image(pw.MemoryImage(proofImage),
                    fit: pw.BoxFit.contain),
              )
            else
              pw.Text('(proof on file)',
                  style: pw.TextStyle(
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey700)),
          ],
        );
      },
    ),
  );

  return doc.save();
}

pw.Widget _row(String label, String value, {bool bold = false}) {
  final style = bold
      ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
      : const pw.TextStyle();
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: style),
        pw.Text(value, style: style),
      ],
    ),
  );
}

pw.Widget _denominationTable(FundAudit audit) {
  // Show all rows in canonical descending order so the certificate matches the
  // count grid; zero-count rows included for completeness.
  final byDenom = {
    for (final d in audit.denominations) d.denomination: d.count,
  };
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    columnWidths: const {
      0: pw.FlexColumnWidth(2),
      1: pw.FlexColumnWidth(1),
      2: pw.FlexColumnWidth(2),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _cell('Denomination', bold: true),
          _cell('Count', bold: true),
          _cell('Subtotal', bold: true),
        ],
      ),
      for (final d in kDenominationsDescending)
        pw.TableRow(children: [
          _cell(_asciiDenom(d)),
          _cell('${byDenom[d] ?? 0}'),
          _cell(_pdfPeso(d.centavos * (byDenom[d] ?? 0))),
        ]),
    ],
  );
}

/// ASCII denomination label (no ₱ glyph).
String _asciiDenom(Denomination d) => switch (d) {
      Denomination.c01 => 'PHP 0.01',
      Denomination.c05 => 'PHP 0.05',
      Denomination.c10 => 'PHP 0.10',
      Denomination.c25 => 'PHP 0.25',
      Denomination.p1 => 'PHP 1',
      Denomination.p5 => 'PHP 5',
      Denomination.p10 => 'PHP 10',
      Denomination.p20 => 'PHP 20',
      Denomination.p50 => 'PHP 50',
      Denomination.p100 => 'PHP 100',
      Denomination.p200 => 'PHP 200',
      Denomination.p500 => 'PHP 500',
      Denomination.p1000 => 'PHP 1,000',
    };

pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: pw.Text(text,
          style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
    );

Future<Uint8List?> _fetchProofImage(String url, http.Client? client) async {
  if (url.isEmpty) return null;
  final c = client ?? http.Client();
  try {
    final resp =
        await c.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
    return resp.bodyBytes;
  } catch (e) {
    // Graceful fallback — the certificate still exports without the photo.
    developer.log('proof image fetch failed for certificate',
        name: 'fund_audit_pdf', error: e);
    return null;
  } finally {
    if (client == null) c.close();
  }
}
