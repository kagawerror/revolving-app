import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/reports/domain/report_csv.dart';
import 'package:rev_app/features/reports/domain/report_models.dart';
import 'package:rev_app/features/reports/domain/report_pdf.dart';
import 'package:rev_app/features/reports/domain/report_period.dart';
import 'package:rev_app/features/reports/domain/report_xlsx.dart';
import 'package:rev_app/services/share/report_share_service.dart';

ReportSummary<ReleasedRequestRow> releasedSummary(
    List<ReleasedRequestRow> rows) {
  final total = rows.fold<int>(0, (a, r) => a + r.amount.centavos);
  return ReportSummary(
    rows: rows,
    grandTotal: Money.fromCentavos(total),
    period: ReportPeriod(
      granularity: PeriodGranularity.month,
      anchor: DateTime(2026, 6, 1),
    ),
  );
}

ReportSummary<ReplenishmentRow> replSummary(List<ReplenishmentRow> rows) {
  final total = rows.fold<int>(0, (a, r) => a + r.total.centavos);
  return ReportSummary(
    rows: rows,
    grandTotal: Money.fromCentavos(total),
    period: ReportPeriod(
      granularity: PeriodGranularity.month,
      anchor: DateTime(2026, 6, 1),
    ),
  );
}

void main() {
  group('moneyPesosBare', () {
    test('formats centavos as bare pesos with two decimals, no symbol', () {
      expect(moneyPesosBare(Money.fromCentavos(123450)), '1234.50');
      expect(moneyPesosBare(Money.fromCentavos(5)), '0.05');
      expect(moneyPesosBare(Money.fromCentavos(100)), '1.00');
      expect(moneyPesosBare(Money.zero), '0.00');
    });
  });

  group('csvField (RFC-4180)', () {
    test('plain values pass through', () {
      expect(csvField('Jane'), 'Jane');
    });
    test('quotes fields with commas', () {
      expect(csvField('Doe, Jane'), '"Doe, Jane"');
    });
    test('doubles inner quotes and wraps', () {
      expect(csvField('say "hi"'), '"say ""hi"""');
    });
    test('quotes newlines and edge whitespace', () {
      expect(csvField('line1\nline2'), '"line1\nline2"');
      expect(csvField(' padded '), '" padded "');
    });
  });

  group('releasedReportCsv', () {
    test('header + rows + grand total, amounts bare pesos', () {
      final csv = releasedReportCsv(
        releasedSummary([
          ReleasedRequestRow(
            requestId: 'r1',
            beneficiaryName: 'Doe, Jane',
            purpose: 'Fuel "premium"',
            amount: Money.fromCentavos(125000),
            effectiveDate: DateTime(2026, 6, 13),
            datePending: false,
            fundName: '',
          ),
        ]),
        'June 2026',
        '',
      );
      final lines = csv.trimRight().split('\n');
      expect(lines.first, 'Requestor,Purpose,Date,Amount,Pending sync');
      // A blank fund name groups under the 'Unassigned' fund banner, then the
      // detail row, then a per-fund subtotal.
      expect(lines[1], 'Fund,Unassigned');
      expect(lines[2],
          '"Doe, Jane","Fuel ""premium""",2026-06-13,1250.00,no');
      expect(lines[3], 'Subtotal,,,1250.00,');
      expect(lines.last, 'GRAND TOTAL,June 2026,,1250.00,');
      // No peso symbol anywhere.
      expect(csv.contains('₱'), isFalse);
    });

    test('prepends Company metadata line when companyName is provided', () {
      final csv = releasedReportCsv(
        releasedSummary([
          ReleasedRequestRow(
            requestId: 'r1',
            beneficiaryName: 'Jane',
            purpose: 'Fuel',
            amount: Money.fromCentavos(10000),
            effectiveDate: DateTime(2026, 6, 13),
            datePending: false,
            fundName: '',
          ),
        ]),
        'June 2026',
        'Acme, Inc.',
      );
      final lines = csv.split('\n');
      // Company line first (quoted because of the comma), then a blank spacer,
      // then the column header row.
      expect(lines.first, 'Company,"Acme, Inc."');
      expect(lines[1], '');
      expect(lines[2], 'Requestor,Purpose,Date,Amount,Pending sync');
    });

    test('omits Company line cleanly when companyName is empty', () {
      final csv = releasedReportCsv(
        releasedSummary([
          ReleasedRequestRow(
            requestId: 'r1',
            beneficiaryName: 'Jane',
            purpose: 'Fuel',
            amount: Money.fromCentavos(10000),
            effectiveDate: DateTime(2026, 6, 13),
            datePending: false,
            fundName: '',
          ),
        ]),
        'June 2026',
        '',
      );
      expect(csv.startsWith('Company'), isFalse);
      // No leading blank gap: the header row is first, not a blank line. (A
      // blank separator DOES appear after each fund group, so we only assert
      // the start is clean rather than the whole file being gap-free.)
      expect(csv.startsWith('\n'), isFalse, reason: 'no leading blank gap');
      expect(csv.split('\n').first, 'Requestor,Purpose,Date,Amount,Pending sync');
    });
  });

  group('replenishmentReportCsv', () {
    test('header + rows + grand total', () {
      final csv = replenishmentReportCsv(
        replSummary([
          ReplenishmentRow(
            replenishmentId: 'p1',
            itemCount: 3,
            total: Money.fromCentavos(500000),
            approvedDate: DateTime(2026, 6, 10),
          ),
        ]),
        'June 2026',
        '',
      );
      final lines = csv.trimRight().split('\n');
      expect(lines.first, 'Approved date,Requests,Total');
      expect(lines[1], '2026-06-10,3,5000.00');
      expect(lines.last, 'GRAND TOTAL (June 2026),,5000.00');
    });
  });

  group('encodeCsvBytes (UTF-8)', () {
    test('round-trips accented chars and en-dash through utf8.decode', () {
      // A week-style period label uses an en-dash (U+2013), and free-text
      // fields carry accented characters — both are non-ASCII and break when
      // UTF-16 code units are truncated to bytes.
      const periodLabel = 'Jun 9–15, 2026';
      final csv = releasedReportCsv(
        releasedSummary([
          ReleasedRequestRow(
            requestId: 'r1',
            beneficiaryName: 'José Niño',
            purpose: 'Café — déjà vu',
            amount: Money.fromCentavos(125000),
            effectiveDate: DateTime(2026, 6, 13),
            datePending: false,
            fundName: '',
          ),
        ]),
        periodLabel,
        '',
      );

      // Encode through the SAME path the share service writes to disk.
      final bytes = encodeCsvBytes(csv);

      // A correct UTF-8 round-trip preserves every character exactly.
      final decoded = utf8.decode(bytes);
      expect(decoded, csv);
      expect(decoded.contains('José Niño'), isTrue);
      expect(decoded.contains('Café — déjà vu'), isTrue);
      expect(decoded.contains('–'), isTrue, reason: 'en-dash must survive');
    });
  });

  group('xlsx builders', () {
    test('released xlsx is a non-empty PK zip', () {
      final bytes = releasedReportXlsx(
        releasedSummary([
          ReleasedRequestRow(
            requestId: 'r1',
            beneficiaryName: 'Jane',
            purpose: 'Fuel',
            amount: Money.fromCentavos(10000),
            effectiveDate: DateTime(2026, 6, 13),
            datePending: false,
            fundName: '',
          ),
        ]),
        'June 2026',
        '',
      );
      expect(bytes.length, greaterThan(0));
      // PK zip magic header.
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
    });

    test('replenishment xlsx is a non-empty PK zip', () {
      final bytes = replenishmentReportXlsx(
        replSummary([
          ReplenishmentRow(
            replenishmentId: 'p1',
            itemCount: 2,
            total: Money.fromCentavos(20000),
            approvedDate: DateTime(2026, 6, 10),
          ),
        ]),
        'June 2026',
        '',
      );
      expect(bytes.length, greaterThan(0));
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
    });
  });

  group('pdf builders', () {
    test('released pdf starts with %PDF', () async {
      final bytes = await releasedReportPdf(
        releasedSummary([
          ReleasedRequestRow(
            requestId: 'r1',
            beneficiaryName: 'Jane',
            purpose: 'Fuel',
            amount: Money.fromCentavos(10000),
            effectiveDate: DateTime(2026, 6, 13),
            datePending: true,
            fundName: '',
          ),
        ]),
        'June 2026',
        'Acme Corp',
      );
      expect(bytes.length, greaterThan(0));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('replenishment pdf starts with %PDF', () async {
      final bytes = await replenishmentReportPdf(
        replSummary([
          ReplenishmentRow(
            replenishmentId: 'p1',
            itemCount: 2,
            total: Money.fromCentavos(20000),
            approvedDate: DateTime(2026, 6, 10),
          ),
        ]),
        'June 2026',
        '',
      );
      expect(bytes.length, greaterThan(0));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });
}
