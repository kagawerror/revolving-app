import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../core/money/money.dart';
import 'report_models.dart';

/// Amounts go in as numeric (pesos) cell values so the spreadsheet can sum/format
/// them; we round centavos/100 to two decimals deterministically.
double _pesos(Money m) => m.centavos / 100.0;

/// .xlsx workbook for the released-requests report: header row, one data row per
/// release (amount as a number), and a bold-ish GRAND TOTAL row. Returns the
/// encoded bytes (PK zip).
Uint8List releasedReportXlsx(
  ReportSummary<ReleasedRequestRow> summary,
  String periodLabel,
) {
  final excel = Excel.createExcel();
  final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(sheetName, 'Released');
  final sheet = excel['Released'];

  sheet.appendRow(<CellValue?>[
    TextCellValue('Beneficiary'),
    TextCellValue('Purpose'),
    TextCellValue('Date'),
    TextCellValue('Amount'),
    TextCellValue('Pending sync'),
  ]);
  for (final r in summary.rows) {
    sheet.appendRow(<CellValue?>[
      TextCellValue(r.beneficiaryName),
      TextCellValue(r.purpose),
      TextCellValue(_iso(r.effectiveDate)),
      DoubleCellValue(_pesos(r.amount)),
      TextCellValue(r.datePending ? 'yes' : 'no'),
    ]);
  }
  sheet.appendRow(<CellValue?>[
    TextCellValue('GRAND TOTAL'),
    TextCellValue(periodLabel),
    null,
    DoubleCellValue(_pesos(summary.grandTotal)),
    null,
  ]);

  return Uint8List.fromList(excel.encode() ?? const <int>[]);
}

/// .xlsx workbook for the replenishments report.
Uint8List replenishmentReportXlsx(
  ReportSummary<ReplenishmentRow> summary,
  String periodLabel,
) {
  final excel = Excel.createExcel();
  final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(sheetName, 'Replenishments');
  final sheet = excel['Replenishments'];

  sheet.appendRow(<CellValue?>[
    TextCellValue('Approved date'),
    TextCellValue('Requests'),
    TextCellValue('Total'),
  ]);
  for (final r in summary.rows) {
    final date = r.approvedDate ?? r.createdDate;
    sheet.appendRow(<CellValue?>[
      TextCellValue(date == null ? '' : _iso(date)),
      IntCellValue(r.itemCount),
      DoubleCellValue(_pesos(r.total)),
    ]);
  }
  sheet.appendRow(<CellValue?>[
    TextCellValue('GRAND TOTAL ($periodLabel)'),
    null,
    DoubleCellValue(_pesos(summary.grandTotal)),
  ]);

  return Uint8List.fromList(excel.encode() ?? const <int>[]);
}

/// .xlsx workbook for the DETAILED replenishment report: one data row per
/// replenished request (amount numeric) + a GRAND TOTAL row.
Uint8List replenishmentDetailXlsx(
  ReportSummary<ReplenishedLineRow> summary,
  String periodLabel,
) {
  final excel = Excel.createExcel();
  final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(sheetName, 'Replenishment detail');
  final sheet = excel['Replenishment detail'];

  sheet.appendRow(<CellValue?>[
    TextCellValue('Approved date'),
    TextCellValue('Fund'),
    TextCellValue('Beneficiary'),
    TextCellValue('Purpose'),
    TextCellValue('Type'),
    TextCellValue('Amount'),
  ]);
  for (final r in summary.rows) {
    sheet.appendRow(<CellValue?>[
      TextCellValue(r.approvedDate == null ? '' : _iso(r.approvedDate!)),
      TextCellValue(r.fundName),
      TextCellValue(r.beneficiaryName),
      TextCellValue(r.purpose),
      TextCellValue(r.isPartial ? 'Partial' : 'Full'),
      DoubleCellValue(_pesos(r.amount)),
    ]);
  }
  sheet.appendRow(<CellValue?>[
    TextCellValue('GRAND TOTAL ($periodLabel)'),
    null,
    null,
    null,
    null,
    DoubleCellValue(_pesos(summary.grandTotal)),
  ]);

  return Uint8List.fromList(excel.encode() ?? const <int>[]);
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
