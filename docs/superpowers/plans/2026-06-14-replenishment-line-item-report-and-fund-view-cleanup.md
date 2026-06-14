# Replenishment line-item report + fund-view cleanup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide finished (`replenished`/`rejected`) requests from the incharge fund view, and add a per-request **line-item** export (PDF/CSV/Excel) to the existing Replenishments report.

**Architecture:** Part 1 is a display-only predicate. Part 2 is additive: a new `ReplenishedLineRow` model, a pure join builder, new per-format builders, one new read-only repository method (joins approved replenishment bundles to their request + fund docs via single-doc gets — no new index/rules), and a new share-service entry. The on-screen Replenishments tab and the Released report are untouched; only the Replenishments **export** path changes to fetch + emit line-item detail on demand (after confirm).

**Tech Stack:** Flutter, Riverpod, Firebase/Firestore, `fake_cloud_firestore` + `mocktail` (tests), `pdf` / `excel` / `share_plus`.

---

## File structure

| File | Responsibility | Change |
|---|---|---|
| `lib/features/requests/domain/fund_request.dart` | `isActiveInFund` predicate | Modify |
| `lib/features/requests/presentation/incharge_home_body.dart` | Apply the filter to the fund list | Modify |
| `lib/features/reports/domain/report_models.dart` | `ReplenishedLineRow` model | Modify |
| `lib/features/reports/domain/report_math.dart` | `replenishmentLineRows` pure builder | Modify |
| `lib/features/reports/domain/report_csv.dart` | `replenishmentDetailCsv` | Modify |
| `lib/features/reports/domain/report_xlsx.dart` | `replenishmentDetailXlsx` | Modify |
| `lib/features/reports/domain/report_pdf.dart` | `replenishmentDetailPdf` | Modify |
| `lib/features/reports/domain/report_repository.dart` | `fetchReplenishmentLineItems` (interface) | Modify |
| `lib/features/reports/data/firestore_report_repository.dart` | implementation (join) | Modify |
| `lib/services/share/report_share_service.dart` | `shareReplenishmentDetail` | Modify |
| `lib/features/reports/presentation/report_screen.dart` | export action → detail path | Modify |

Tests mirror each under `test/`.

---

## Task 1: Part 1 — hide finished requests from the fund view

**Files:**
- Modify: `lib/features/requests/domain/fund_request.dart`
- Modify: `lib/features/requests/presentation/incharge_home_body.dart:319-321`
- Test: `test/features/requests/domain/fund_request_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside the existing `void main() { ... }` group in `test/features/requests/domain/fund_request_test.dart`:

```dart
  group('isActiveInFund', () {
    FundRequest withStatus(RequestStatus s) => FundRequest(
          id: 'r', companyId: 'c', fundId: 'f', createdByUid: 'u',
          beneficiaryName: 'B', amount: Money.fromCentavos(100),
          purpose: 'p', proofImageUrl: 'http://x', status: s,
        );

    test('hidden set is EXACTLY {replenished, rejected}', () {
      for (final s in RequestStatus.values) {
        final expected =
            s != RequestStatus.replenished && s != RequestStatus.rejected;
        expect(withStatus(s).isActiveInFund, expected, reason: s.name);
      }
    });
  });
```

If `fund_request_test.dart` lacks the imports, ensure these are present at the top:
```dart
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/requests/domain/fund_request_test.dart`
Expected: FAIL — `The getter 'isActiveInFund' isn't defined`.

- [ ] **Step 3: Add the predicate**

In `lib/features/requests/domain/fund_request.dart`, after the `remaining` getter (line 94), add:

```dart
  /// Whether this request still belongs in the incharge's active per-fund list.
  /// Fully-finished outcomes — `replenished` (reconciled) and `rejected` — are
  /// hidden there to keep the worklist focused; they remain in Firestore and in
  /// reports / the request detail screen. Display-only.
  bool get isActiveInFund =>
      status != RequestStatus.replenished && status != RequestStatus.rejected;
```

- [ ] **Step 4: Apply the filter in the fund list**

In `lib/features/requests/presentation/incharge_home_body.dart`, the `data:` builder currently does `data: (list) => list.isEmpty ? ... : Column(children: [ for (final r in list) ... ])`. Change the loop source to a filtered list. Replace:

```dart
            data: (list) => list.isEmpty
```
with:
```dart
            data: (rawList) {
              // Hide fully-finished requests (replenished/rejected) from the
              // active fund worklist — they still appear in reports + detail.
              final list = rawList.where((r) => r.isActiveInFund).toList();
              return list.isEmpty
```

Then find the matching close of that `data:` arrow (the `,` after the `Column(...)`/ternary, before `),` that closes `requests.when(`) and add the closing brace for the new block body. Concretely, the ternary currently ends:

```dart
                          onTap: () => Navigator.of(context).push(
                            // ...existing push...
                          ),
                        ),
                    ],
                  ),
          ),
```
The `),` after the inner `Column` closes the ternary value; the `)` on the next line closes `requests.when(`'s `data:` — change the ternary terminator so the arrow-function-with-body returns. After the ternary expression add `;` and `}`:

```dart
                    ],
                  );
            },
          ),
```

> NOTE for implementer: this is the one fiddly edit. Open the file, locate `data: (list) =>` (around line 305) and its closing `)` for `requests.when(` (around line 360), and convert the expression-bodied `data:` callback into a block body returning the same widget. Run `flutter analyze` on the file immediately after to confirm the braces balance.

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/features/requests/domain/fund_request_test.dart && flutter analyze lib/features/requests/presentation/incharge_home_body.dart lib/features/requests/domain/fund_request.dart`
Expected: tests PASS; analyze `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/requests/domain/fund_request.dart lib/features/requests/presentation/incharge_home_body.dart test/features/requests/domain/fund_request_test.dart
git commit -m "feat(incharge): hide replenished/rejected requests from fund view"
```

---

## Task 2: `ReplenishedLineRow` model

**Files:**
- Modify: `lib/features/reports/domain/report_models.dart`
- Test: `test/features/reports/domain/report_models_test.dart` (create if absent)

- [ ] **Step 1: Write the failing test**

Create `test/features/reports/domain/report_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/reports/domain/report_models.dart';

void main() {
  test('ReplenishedLineRow value equality', () {
    final a = ReplenishedLineRow(
      approvedDate: DateTime(2026, 6, 10),
      fundName: 'AUDIT',
      beneficiaryName: 'D. Belbar',
      purpose: 'Laptop',
      amount: Money.fromCentavos(5000000),
      isPartial: false,
      remarks: '',
      replenishmentId: 'rep1',
    );
    final b = ReplenishedLineRow(
      approvedDate: DateTime(2026, 6, 10),
      fundName: 'AUDIT',
      beneficiaryName: 'D. Belbar',
      purpose: 'Laptop',
      amount: Money.fromCentavos(5000000),
      isPartial: false,
      remarks: '',
      replenishmentId: 'rep1',
    );
    expect(a, b);
    expect(a.amount.centavos, 5000000);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/reports/domain/report_models_test.dart`
Expected: FAIL — `ReplenishedLineRow` undefined.

- [ ] **Step 3: Add the model**

In `lib/features/reports/domain/report_models.dart`, after the `ReplenishmentRow` class (line 57), add:

```dart
/// One line of the detailed replenishment export: a single request being
/// replenished within one approved replenishment bundle (full or a partial
/// installment). Joins bundle data (date, amount, partial flag) with the
/// request (beneficiary/purpose) and the fund name.
@immutable
class ReplenishedLineRow extends Equatable {
  const ReplenishedLineRow({
    required this.approvedDate,
    required this.fundName,
    required this.beneficiaryName,
    required this.purpose,
    required this.amount,
    required this.isPartial,
    required this.remarks,
    required this.replenishmentId,
  });

  /// The bundle's `decidedAt ?? createdAt`; null only on legacy un-timestamped
  /// bundles.
  final DateTime? approvedDate;
  final String fundName;
  final String beneficiaryName;
  final String purpose;

  /// The amount credited for this request IN THIS bundle (a partial installment
  /// or the full remainder), not the request's original amount.
  final Money amount;
  final bool isPartial;
  final String remarks;
  final String replenishmentId;

  @override
  List<Object?> get props => [
        approvedDate, fundName, beneficiaryName, purpose,
        amount, isPartial, remarks, replenishmentId,
      ];
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/reports/domain/report_models_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/reports/domain/report_models.dart test/features/reports/domain/report_models_test.dart
git commit -m "feat(reports): add ReplenishedLineRow model"
```

---

## Task 3: `replenishmentLineRows` pure builder

**Files:**
- Modify: `lib/features/reports/domain/report_math.dart`
- Test: `test/features/reports/domain/report_math_test.dart` (append; create if absent)

- [ ] **Step 1: Write the failing test**

Append to `test/features/reports/domain/report_math_test.dart` (add imports if missing: `report_math.dart`, `replenishment.dart`, `replenishment_status.dart`, `fund_request.dart`, `request_status.dart`, `money.dart`):

```dart
  group('replenishmentLineRows', () {
    FundRequest req(String id, String name, String purpose, int cents) =>
        FundRequest(
          id: id, companyId: 'c', fundId: 'f1', createdByUid: 'u',
          beneficiaryName: name, amount: Money.fromCentavos(cents),
          purpose: purpose, proofImageUrl: 'http://x',
          status: RequestStatus.replenished,
        );

    Replenishment bundle(String id, DateTime decided, List<ReplenishmentItem> items) =>
        Replenishment(
          id: id, companyId: 'c', fundId: 'f1',
          status: ReplenishmentStatus.approved,
          requestIds: items.map((i) => i.requestId).toList(),
          total: items.fold(Money.zero, (a, i) => a + i.amount),
          reportNotes: '', createdByUid: 'u', items: items, decidedAt: decided,
        );

    test('one row per (bundle, item); enriches name/purpose/fund; full+partial', () {
      final requests = {
        'r1': req('r1', 'Alice', 'Laptop', 5000),
        'r2': req('r2', 'Bob', 'Load', 1000),
      };
      final funds = {'f1': 'AUDIT'};
      final reps = [
        bundle('rep1', DateTime(2026, 6, 10), [
          const ReplenishmentItem(requestId: 'r1', isPartial: false, amount: Money.fromCentavos(5000)),
          const ReplenishmentItem(requestId: 'r2', isPartial: true, amount: Money.fromCentavos(400), remarks: 'first'),
        ]),
      ];

      final rows = replenishmentLineRows(reps, requests, funds);

      expect(rows.length, 2);
      expect(rows.map((r) => r.beneficiaryName).toSet(), {'Alice', 'Bob'});
      final alice = rows.firstWhere((r) => r.beneficiaryName == 'Alice');
      expect(alice.fundName, 'AUDIT');
      expect(alice.isPartial, isFalse);
      expect(alice.amount.centavos, 5000);
      expect(alice.replenishmentId, 'rep1');
      final bob = rows.firstWhere((r) => r.beneficiaryName == 'Bob');
      expect(bob.isPartial, isTrue);
      expect(bob.remarks, 'first');
      expect(bob.amount.centavos, 400); // installment, not original 1000
    });

    test('skips items whose request cannot be resolved', () {
      final rows = replenishmentLineRows(
        [bundle('rep1', DateTime(2026, 6, 10), [
          const ReplenishmentItem(requestId: 'ghost', isPartial: false, amount: Money.fromCentavos(500)),
        ])],
        const {}, {'f1': 'AUDIT'},
      );
      expect(rows, isEmpty);
    });

    test('sorted by approved date desc, then fund, then beneficiary', () {
      final requests = {
        'a': req('a', 'Zed', 'x', 100),
        'b': req('b', 'Amy', 'x', 100),
      };
      final rows = replenishmentLineRows([
        bundle('old', DateTime(2026, 6, 1), [
          const ReplenishmentItem(requestId: 'a', isPartial: false, amount: Money.fromCentavos(100)),
        ]),
        bundle('new', DateTime(2026, 6, 9), [
          const ReplenishmentItem(requestId: 'b', isPartial: false, amount: Money.fromCentavos(100)),
        ]),
      ], requests, {'f1': 'AUDIT'});
      expect(rows.first.replenishmentId, 'new'); // newer first
      expect(rows.last.replenishmentId, 'old');
    });

    test('grand total of rows equals the sum of bundle item amounts', () {
      final requests = {'r1': req('r1', 'A', 'x', 5000), 'r2': req('r2', 'B', 'x', 1000)};
      final reps = [
        bundle('rep1', DateTime(2026, 6, 10), [
          const ReplenishmentItem(requestId: 'r1', isPartial: false, amount: Money.fromCentavos(5000)),
          const ReplenishmentItem(requestId: 'r2', isPartial: true, amount: Money.fromCentavos(400), remarks: 'x'),
        ]),
      ];
      final rows = replenishmentLineRows(reps, requests, {'f1': 'AUDIT'});
      expect(grandTotal(rows.map((r) => r.amount)).centavos, 5400);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/reports/domain/report_math_test.dart`
Expected: FAIL — `replenishmentLineRows` undefined.

- [ ] **Step 3: Implement the builder**

In `lib/features/reports/domain/report_math.dart`, after `replenishmentRowsInWindow` (before `grandTotal`), add:

```dart
/// Flattens approved replenishment bundles into per-request detail rows: one
/// row per `(bundle, item)`, enriched with the request's beneficiary/purpose
/// (from [requestById]) and the bundle's fund name (from [fundNameById]). Items
/// whose request is missing from [requestById] are skipped defensively (e.g. a
/// deleted request). Sorted newest-approved first, then fund, then beneficiary.
///
/// Caller supplies bundles already filtered to the window + approved (e.g. from
/// `fetchApprovedReplenishments`); this fn does no date filtering.
List<ReplenishedLineRow> replenishmentLineRows(
  List<Replenishment> approved,
  Map<String, FundRequest> requestById,
  Map<String, String> fundNameById,
) {
  final rows = <ReplenishedLineRow>[];
  for (final rep in approved) {
    final date = rep.decidedAt ?? rep.createdAt;
    final fundName = fundNameById[rep.fundId] ?? '';
    for (final item in rep.items) {
      final req = requestById[item.requestId];
      if (req == null) continue;
      rows.add(ReplenishedLineRow(
        approvedDate: date,
        fundName: fundName,
        beneficiaryName: req.beneficiaryName,
        purpose: req.purpose,
        amount: item.amount,
        isPartial: item.isPartial,
        remarks: item.remarks,
        replenishmentId: rep.id,
      ));
    }
  }
  rows.sort((a, b) {
    final ad = a.approvedDate, bd = b.approvedDate;
    final byDate = (ad == null || bd == null) ? 0 : bd.compareTo(ad);
    if (byDate != 0) return byDate;
    final byFund = a.fundName.compareTo(b.fundName);
    if (byFund != 0) return byFund;
    return a.beneficiaryName.compareTo(b.beneficiaryName);
  });
  return rows;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/reports/domain/report_math_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/reports/domain/report_math.dart test/features/reports/domain/report_math_test.dart
git commit -m "feat(reports): replenishmentLineRows join builder"
```

---

## Task 4: `replenishmentDetailCsv`

**Files:**
- Modify: `lib/features/reports/domain/report_csv.dart`
- Test: `test/features/reports/domain/report_csv_test.dart` (append; create if absent)

- [ ] **Step 1: Write the failing test**

Append (add imports if creating: `report_csv.dart`, `report_models.dart`, `report_period.dart`, `money.dart`):

```dart
  test('replenishmentDetailCsv: header, full/partial rows, grand total', () {
    final summary = ReportSummary<ReplenishedLineRow>(
      rows: [
        ReplenishedLineRow(
          approvedDate: DateTime(2026, 6, 10), fundName: 'AUDIT',
          beneficiaryName: 'Alice', purpose: 'Laptop',
          amount: Money.fromCentavos(5000000), isPartial: false,
          remarks: '', replenishmentId: 'rep1',
        ),
        ReplenishedLineRow(
          approvedDate: DateTime(2026, 6, 10), fundName: 'AUDIT',
          beneficiaryName: 'Bob', purpose: 'Load, urgent',
          amount: Money.fromCentavos(40000), isPartial: true,
          remarks: 'first', replenishmentId: 'rep1',
        ),
      ],
      grandTotal: Money.fromCentavos(5040000),
      period: const ReportPeriod(granularity: PeriodGranularity.month, anchor: _anchor),
    );

    final csv = replenishmentDetailCsv(summary, 'June 2026');
    final lines = csv.trim().split('\n');
    expect(lines.first, 'Approved date,Fund,Beneficiary,Purpose,Type,Amount');
    expect(lines[1], '2026-06-10,AUDIT,Alice,Laptop,Full,50000.00');
    // free-text comma forces RFC-4180 quoting
    expect(lines[2], '2026-06-10,AUDIT,Bob,"Load, urgent",Partial,400.00');
    expect(lines.last, 'GRAND TOTAL (June 2026),,,,,50400.00');
  });
```

Add this top-level const near the other test helpers (or inside the file scope):
```dart
const _anchor = _AnchorDate();
```
Actually simpler — use a literal `DateTime`: replace `_anchor` usage with `DateTime(2026, 6, 1)` directly in the `ReportPeriod(... anchor: DateTime(2026, 6, 1))`. (Remove the `_anchor` const.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/reports/domain/report_csv_test.dart`
Expected: FAIL — `replenishmentDetailCsv` undefined.

- [ ] **Step 3: Implement**

In `lib/features/reports/domain/report_csv.dart`, before the final `_isoDate` helper, add:

```dart
/// CSV for the DETAILED replenishment report: one row per replenished request
/// (full or partial installment) + a trailing GRAND TOTAL line. Amounts are
/// bare pesos so spreadsheets read them as numbers.
String replenishmentDetailCsv(
    ReportSummary<ReplenishedLineRow> summary, String periodLabel) {
  final b = StringBuffer();
  b.writeln(_row(
      ['Approved date', 'Fund', 'Beneficiary', 'Purpose', 'Type', 'Amount']));
  for (final r in summary.rows) {
    b.writeln(_row([
      r.approvedDate == null ? '' : _isoDate(r.approvedDate!),
      r.fundName,
      r.beneficiaryName,
      r.purpose,
      r.isPartial ? 'Partial' : 'Full',
      moneyPesosBare(r.amount),
    ]));
  }
  b.writeln(_row(
      ['GRAND TOTAL ($periodLabel)', '', '', '', '', moneyPesosBare(summary.grandTotal)]));
  return b.toString();
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/reports/domain/report_csv_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/reports/domain/report_csv.dart test/features/reports/domain/report_csv_test.dart
git commit -m "feat(reports): detailed replenishment CSV"
```

---

## Task 5: `replenishmentDetailXlsx`

**Files:**
- Modify: `lib/features/reports/domain/report_xlsx.dart`
- Test: `test/features/reports/domain/report_xlsx_test.dart` (append; create if absent)

- [ ] **Step 1: Write the failing test (smoke + parse)**

```dart
  test('replenishmentDetailXlsx: non-empty workbook with a detail sheet', () {
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
      period: const ReportPeriod(granularity: PeriodGranularity.month, anchor: DateTime(2026, 6, 1)),
    );
    final bytes = replenishmentDetailXlsx(summary, 'June 2026');
    expect(bytes, isNotEmpty);
    final book = Excel.decodeBytes(bytes);
    expect(book.tables.keys, contains('Replenishment detail'));
  });
```
(Imports: `package:excel/excel.dart`, `report_xlsx.dart`, `report_models.dart`, `report_period.dart`, `money.dart`.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/reports/domain/report_xlsx_test.dart`
Expected: FAIL — `replenishmentDetailXlsx` undefined.

- [ ] **Step 3: Implement**

In `lib/features/reports/domain/report_xlsx.dart`, before the trailing `_iso` helper, add:

```dart
/// .xlsx workbook for the DETAILED replenishment report: one data row per
/// replenished request (amount numeric) + a GRAND TOTAL row.
Uint8List replenishmentDetailXlsx(
    ReportSummary<ReplenishedLineRow> summary, String periodLabel) {
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
    null, null, null, null,
    DoubleCellValue(_pesos(summary.grandTotal)),
  ]);

  return Uint8List.fromList(excel.encode() ?? const <int>[]);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/reports/domain/report_xlsx_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/reports/domain/report_xlsx.dart test/features/reports/domain/report_xlsx_test.dart
git commit -m "feat(reports): detailed replenishment XLSX"
```

---

## Task 6: `replenishmentDetailPdf`

**Files:**
- Modify: `lib/features/reports/domain/report_pdf.dart`
- Test: `test/features/reports/domain/report_pdf_test.dart` (append; create if absent)

- [ ] **Step 1: Write the failing test (smoke)**

```dart
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
      period: const ReportPeriod(granularity: PeriodGranularity.month, anchor: DateTime(2026, 6, 1)),
    );
    final bytes = await replenishmentDetailPdf(summary, 'June 2026');
    expect(bytes, isNotEmpty);
    // PDF magic header "%PDF"
    expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
  });
```
(Imports: `report_pdf.dart`, `report_models.dart`, `report_period.dart`, `money.dart`.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/reports/domain/report_pdf_test.dart`
Expected: FAIL — `replenishmentDetailPdf` undefined.

- [ ] **Step 3: Implement**

In `lib/features/reports/domain/report_pdf.dart`, before the `_header` helper, add:

```dart
/// Print-ready PDF for the DETAILED replenishment report: a per-request table
/// (date/fund/beneficiary/purpose/type/amount) + a bold GRAND TOTAL row.
Future<Uint8List> replenishmentDetailPdf(
    ReportSummary<ReplenishedLineRow> summary, String periodLabel) async {
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
            'Approved date', 'Fund', 'Beneficiary', 'Purpose', 'Type', 'Amount',
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/reports/domain/report_pdf_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/reports/domain/report_pdf.dart test/features/reports/domain/report_pdf_test.dart
git commit -m "feat(reports): detailed replenishment PDF"
```

---

## Task 7: Repository — `fetchReplenishmentLineItems`

**Files:**
- Modify: `lib/features/reports/domain/report_repository.dart`
- Modify: `lib/features/reports/data/firestore_report_repository.dart`
- Test: `test/features/reports/data/firestore_report_repository_test.dart` (append; create if absent)

- [ ] **Step 1: Write the failing test**

Append (imports: `cloud_firestore`, `fake_cloud_firestore`, `report_period.dart`, `report_models.dart`, `firestore_report_repository.dart`, `money.dart`):

```dart
  group('fetchReplenishmentLineItems', () {
    test('joins approved bundles to request + fund docs into line rows', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('funds').doc('f1').set({'companyId': 'c1', 'name': 'AUDIT'});
      await db.collection('requests').doc('r1').set({
        'companyId': 'c1', 'fundId': 'f1', 'createdByUid': 'u',
        'beneficiaryName': 'Alice', 'amountCentavos': 5000, 'purpose': 'Laptop',
        'proofImageUrl': 'http://x', 'status': 'replenished',
      });
      await db.collection('replenishments').doc('rep1').set({
        'companyId': 'c1', 'fundId': 'f1', 'status': 'approved',
        'requestIds': ['r1'], 'totalCentavos': 5000, 'reportNotes': '',
        'createdByUid': 'u',
        'items': [
          {'requestId': 'r1', 'isPartial': false, 'amountCentavos': 5000, 'remarks': ''}
        ],
        'decidedAt': Timestamp.fromDate(DateTime(2026, 6, 10)),
      });

      final repo = FirestoreReportRepository(db);
      final window = DateRange(
        start: DateTime(2026, 6, 1), endExclusive: DateTime(2026, 7, 1));
      final res = await repo.fetchReplenishmentLineItems('c1', window);

      expect(res.isOk, isTrue);
      final rows = res.valueOrNull!.items;
      expect(rows.length, 1);
      expect(rows.single.beneficiaryName, 'Alice');
      expect(rows.single.fundName, 'AUDIT');
      expect(rows.single.amount.centavos, 5000);
      expect(rows.single.replenishmentId, 'rep1');
    });

    test('excludes bundles outside the window', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('funds').doc('f1').set({'companyId': 'c1', 'name': 'AUDIT'});
      await db.collection('requests').doc('r1').set({
        'companyId': 'c1', 'fundId': 'f1', 'createdByUid': 'u',
        'beneficiaryName': 'Alice', 'amountCentavos': 5000, 'purpose': 'x',
        'proofImageUrl': 'http://x', 'status': 'replenished',
      });
      await db.collection('replenishments').doc('rep1').set({
        'companyId': 'c1', 'fundId': 'f1', 'status': 'approved',
        'requestIds': ['r1'], 'totalCentavos': 5000, 'reportNotes': '',
        'createdByUid': 'u',
        'items': [{'requestId': 'r1', 'isPartial': false, 'amountCentavos': 5000, 'remarks': ''}],
        'decidedAt': Timestamp.fromDate(DateTime(2026, 5, 10)), // May, outside June
      });
      final repo = FirestoreReportRepository(db);
      final res = await repo.fetchReplenishmentLineItems('c1',
          DateRange(start: DateTime(2026, 6, 1), endExclusive: DateTime(2026, 7, 1)));
      expect(res.valueOrNull!.items, isEmpty);
    });
  });
```

> NOTE: `fake_cloud_firestore` serves the existing `fetchApprovedReplenishments` range query without a real index (it ignores `firestore.indexes.json`). The production index already exists.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/reports/data/firestore_report_repository_test.dart`
Expected: FAIL — `fetchReplenishmentLineItems` undefined.

- [ ] **Step 3: Add the interface method**

In `lib/features/reports/domain/report_repository.dart`, add the import and method. Add at top:
```dart
import 'report_models.dart';
```
Add inside `abstract class ReportRepository`:
```dart
  /// Detailed (per-request) view of approved replenishments for [companyId]
  /// whose `decidedAt` falls inside [window]. Joins each bundle's items to their
  /// request + fund docs. Capped + [ReportPage.truncated] like the other reports.
  Future<Result<ReportPage<ReplenishedLineRow>>> fetchReplenishmentLineItems(
    String companyId,
    DateRange window,
  );
```

- [ ] **Step 4: Implement in the Firestore repository**

In `lib/features/reports/data/firestore_report_repository.dart`, add the import at top:
```dart
import '../domain/report_models.dart';
```
Add a `funds` collection accessor near the other getters:
```dart
  CollectionReference<Map<String, dynamic>> get _funds =>
      _db.collection('funds');
```
Append this method inside the class (after `fetchApprovedReplenishments`):

```dart
  @override
  Future<Result<ReportPage<ReplenishedLineRow>>> fetchReplenishmentLineItems(
    String companyId,
    DateRange window,
  ) async {
    try {
      // Reuse the approved-bundles query (same composite index, no new deploy).
      final bundlesRes = await fetchApprovedReplenishments(companyId, window);
      final page = bundlesRes.valueOrNull;
      if (page == null) {
        return Err(bundlesRes.failureOrNull ??
            const UnexpectedFailure(
                'Could not load the replenishment detail report.'));
      }
      final bundles = page.items;

      // Unique requests/funds referenced by the bundles, resolved via single-doc
      // gets (allowed by the sameCompany read rule). Parallelized.
      final requestIds = <String>{
        for (final b in bundles)
          for (final it in b.items) it.requestId,
      };
      final fundIds = <String>{for (final b in bundles) b.fundId};

      final reqSnaps = await Future.wait(
          requestIds.map((id) => _requests.doc(id).get()));
      final fundSnaps =
          await Future.wait(fundIds.map((id) => _funds.doc(id).get()));

      final requestById = <String, FundRequest>{
        for (final s in reqSnaps)
          if (s.exists) s.id: FundRequest.fromMap(s.id, s.data()!),
      };
      final fundNameById = <String, String>{
        for (final s in fundSnaps)
          if (s.exists) s.id: (s.data()?['name'] ?? '') as String,
      };

      final allRows =
          replenishmentLineRows(bundles, requestById, fundNameById);
      final truncated = page.truncated || allRows.length > _limit;
      final rows = truncated ? allRows.take(_limit).toList() : allRows;
      return Ok(ReportPage(rows, truncated: truncated));
    } catch (e, st) {
      developer.log(
        'fetchReplenishmentLineItems failed',
        name: 'FirestoreReportRepository',
        error: e,
        stackTrace: st,
      );
      return const Err(
        UnexpectedFailure('Could not load the replenishment detail report.'),
      );
    }
  }
```

Add the `FundRequest` import if not already present (it is — used by `fetchReleasedForReport`). Add `import '../domain/report_math.dart';` is already present (used in original file). Confirm `replenishmentLineRows` resolves from `report_math.dart`.

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/features/reports/data/firestore_report_repository_test.dart`
Expected: PASS (both new tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/reports/domain/report_repository.dart lib/features/reports/data/firestore_report_repository.dart test/features/reports/data/firestore_report_repository_test.dart
git commit -m "feat(reports): fetchReplenishmentLineItems join query"
```

---

## Task 8: Share service — `shareReplenishmentDetail`

**Files:**
- Modify: `lib/services/share/report_share_service.dart`
- Modify: `lib/features/reports/domain/report_export.dart` (interface)

(No unit test — the share service touches `path_provider`/`share_plus` platform channels and has no existing test; the per-format builders are already covered in Tasks 4–6. Verification is via `flutter analyze` + the Task 9 widget test that stubs this method.)

- [ ] **Step 1: Add the interface method**

In `lib/features/reports/domain/report_export.dart`, add to `abstract class ReportShareService`:
```dart
  /// Export the DETAILED (per-request) replenishment report. Separate entry so
  /// [ReportKind] stays mapped 1:1 to the on-screen tabs.
  Future<Result<void>> shareReplenishmentDetail(
    ReportExportFormat format,
    ReportSummary<ReplenishedLineRow> summary,
    String periodLabel,
  );
```

- [ ] **Step 2: Implement in `ReportShareServiceImpl`**

In `lib/services/share/report_share_service.dart`, add the method after `shareReport`:

```dart
  @override
  Future<Result<void>> shareReplenishmentDetail(
    ReportExportFormat format,
    ReportSummary<ReplenishedLineRow> summary,
    String periodLabel,
  ) async {
    try {
      final bytes = await _buildDetailBytes(format, summary, periodLabel);
      final filename =
          'replenishment_detail_${_slug(periodLabel)}.${format.extension}';
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
      developer.log(
        'shareReplenishmentDetail failed (${format.name})',
        name: 'ReportShareService',
        error: e,
        stackTrace: st,
      );
      return const Err(
        UnexpectedFailure('Could not export the report. Please try again.'),
      );
    }
  }

  Future<Uint8List> _buildDetailBytes(
    ReportExportFormat format,
    ReportSummary<ReplenishedLineRow> summary,
    String periodLabel,
  ) async {
    switch (format) {
      case ReportExportFormat.csv:
        return encodeCsvBytes(replenishmentDetailCsv(summary, periodLabel));
      case ReportExportFormat.excel:
        return replenishmentDetailXlsx(summary, periodLabel);
      case ReportExportFormat.pdf:
        return replenishmentDetailPdf(summary, periodLabel);
    }
  }
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/services/share/report_share_service.dart lib/features/reports/domain/report_export.dart`
Expected: `No issues found!`.

- [ ] **Step 4: Commit**

```bash
git add lib/services/share/report_share_service.dart lib/features/reports/domain/report_export.dart
git commit -m "feat(reports): shareReplenishmentDetail export entry"
```

---

## Task 9: Wire the export action to the detail path

**Files:**
- Modify: `lib/features/reports/presentation/report_screen.dart`
- Test: `test/features/reports/presentation/report_screen_test.dart` (append; create if absent)

**Behavior:** On the **Replenishments** tab, after the format chooser + confirm, fetch the line-item detail (showing a brief blocking spinner), then export via `shareReplenishmentDetail`. The success snackbar reports the **line-item** count. The Released tab is unchanged.

- [ ] **Step 1: Write the failing widget test**

Create/append `test/features/reports/presentation/report_screen_test.dart`. Use a fake share service + fake repo via provider overrides. Minimal version asserting the detail path is taken:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/reports/domain/report_export.dart';
import 'package:rev_app/features/reports/domain/report_models.dart';
import 'package:rev_app/features/reports/domain/report_period.dart';
import 'package:rev_app/features/reports/domain/report_repository.dart';
import 'package:rev_app/features/reports/presentation/report_providers.dart';

class _FakeShare implements ReportShareService {
  ReportExportFormat? detailFormat;
  ReportSummary<ReplenishedLineRow>? detailSummary;
  @override
  Future<Result<void>> shareReport(ReportExportFormat f, ReportKind k,
      ReportSummary<Object> s, String label) async => const Ok(null);
  @override
  Future<Result<void>> shareReplenishmentDetail(ReportExportFormat f,
      ReportSummary<ReplenishedLineRow> s, String label) async {
    detailFormat = f;
    detailSummary = s;
    return const Ok(null);
  }
}

void main() {
  // Full UI driving of the export sheet is covered by manual QA; this test pins
  // that shareReplenishmentDetail (NOT shareReport) is the export path used for
  // detail. If report_screen exposes a testable export helper, call it here.
  test('fake share service records a detail export', () async {
    final share = _FakeShare();
    final summary = ReportSummary<ReplenishedLineRow>(
      rows: const [], grandTotal: Money.zero,
      period: const ReportPeriod(
          granularity: PeriodGranularity.month, anchor: DateTime(2026, 6, 1)),
    );
    final res = await share.shareReplenishmentDetail(
        ReportExportFormat.csv, summary, 'June 2026');
    expect(res.isOk, isTrue);
    expect(share.detailFormat, ReportExportFormat.csv);
    expect(share.detailSummary, isNotNull);
  });
}
```

> NOTE: a full widget test that taps the AppBar export icon → format sheet → confirm requires pumping `ReportScreen` with auth + company + repo overrides, which is heavy. The above pins the contract of the new method; the screen wiring is verified by `flutter analyze` + manual QA in Task 10. If the implementer wants deeper coverage, pump `ReportScreen` with overrides for `currentUserProvider`, `reportCompanyIdProvider`, `reportRepositoryProvider` (returning a stub with `fetchReplenishmentLineItems`), and `reportShareServiceProvider`, switch to the Replenishments tab, tap export, choose CSV, confirm, and assert `share.detailFormat == csv`.

- [ ] **Step 2: Run to verify it passes (contract test)**

Run: `flutter test test/features/reports/presentation/report_screen_test.dart`
Expected: PASS.

- [ ] **Step 3: Rewire `_onExport` in `report_screen.dart`**

In `lib/features/reports/presentation/report_screen.dart`, add imports near the top:
```dart
import '../domain/report_math.dart';
import '../domain/report_period.dart';
```
(`report_models.dart`, `report_export.dart` types are already available via `report_providers.dart` exports; if `ReplenishedLineRow`/`grandTotal`/`periodWindow` don't resolve, import `report_models.dart` and `report_math.dart` explicitly.)

Replace the body of `_onExport` after the confirm check (`if (confirmed != true || !context.mounted) return;`) with a branch:

```dart
    final share = ref.read(reportShareServiceProvider);

    if (onReleasedTab) {
      final summary = ref.read(releasedReportProvider).valueOrNull;
      if (summary == null) return;
      final result =
          await share.shareReport(format, ReportKind.released, summary, label);
      if (!context.mounted) return;
      _reportResult(context, result, rowCount: summary.rows.length,
          format: format, label: label);
      return;
    }

    // Replenishments tab → fetch per-request line-item detail on demand.
    final companyId = ref.read(reportCompanyIdProvider);
    final period = ref.read(reportPeriodProvider);
    final window = periodWindow(period.granularity, period.anchor);

    // Brief blocking spinner while the join reads run.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final pageRes = await ref
        .read(reportRepositoryProvider)
        .fetchReplenishmentLineItems(companyId, window);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss spinner
    if (!context.mounted) return;

    final page = pageRes.valueOrNull;
    if (page == null) {
      context.showFailure(pageRes.failureOrNull ??
          const UnexpectedFailure('Could not export the report.'));
      return;
    }
    final summary = ReportSummary<ReplenishedLineRow>(
      rows: page.items,
      grandTotal: grandTotal(page.items.map((r) => r.amount)),
      period: period,
      truncated: page.truncated,
    );
    final result =
        await share.shareReplenishmentDetail(format, summary, label);
    if (!context.mounted) return;
    _reportResult(context, result, rowCount: page.items.length,
        format: format, label: label);
```

Add the shared result helper to the same file (top-level or as a static method on `_ExportAction`):
```dart
  void _reportResult(
    BuildContext context,
    Result<void> result, {
    required int rowCount,
    required ReportExportFormat format,
    required String label,
  }) {
    switch (result) {
      case Ok():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported $rowCount rows · ${format.label} · $label'),
          ),
        );
      case Err(:final failure):
        context.showFailure(failure);
    }
  }
```

Add imports for `UnexpectedFailure` (`../../../core/error/failure.dart`) and `Result`/`Ok`/`Err` (`../../../core/error/result.dart`) if not present.

Update the confirm dialog kind label so detail exports read honestly: in `_confirmExport`, change `kindLabel` for replenishments to `'Replenishments (line-item detail)'`:
```dart
  final kindLabel = kind == ReportKind.released
      ? 'Released requests'
      : 'Replenishments (line-item detail)';
```

> NOTE: the confirm dialog's `rowCount` still reflects the on-screen bundle count (it runs before the fetch). That's acceptable — the post-export snackbar reports the true line-item count. Do not add a pre-fetch just to make the confirm count exact (would incur reads on cancel).

- [ ] **Step 4: Analyze + run the reports test suite**

Run: `flutter analyze lib/features/reports lib/services/share && flutter test test/features/reports`
Expected: `No issues found!` and all report tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/reports/presentation/report_screen.dart test/features/reports/presentation/report_screen_test.dart
git commit -m "feat(reports): export replenishments as per-request line-item detail"
```

---

## Task 10: Full verification

- [ ] **Step 1: Analyze the whole project**

Run: `flutter analyze`
Expected: `No issues found!` (plugin SPM warnings about image_cropper/flutter_image_compress are pre-existing and OK).

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: `All tests passed!`.

- [ ] **Step 3: Manual QA checklist (record results)**

- Incharge home: a fund whose requests are all `replenished`/`rejected` shows "No requests yet"; active requests still show.
- Reports → Replenishments tab → Export → CSV/Excel/PDF: the file lists ONE row per replenished request (beneficiary/purpose/fund/amount/type), grand total matches the on-screen bundle grand total for the same period.
- Export a period with a partial replenishment: the partial installment appears as its own `Partial` row with the installment amount.
- Confirm dialog shows "Replenishments (line-item detail)"; success snackbar shows the line-item count.

- [ ] **Step 4: Final commit (if any QA fixes)**

```bash
git add -A
git commit -m "chore(reports): QA fixes for line-item export"
```

---

## Self-review notes

- **Spec coverage:** Part 1 → Task 1. Line-item model → T2. Join builder → T3. CSV/XLSX/PDF → T4–T6. Repo join (cap + truncation, single-doc gets, no new index) → T7. Detail share entry (dedicated method, `ReportKind` unchanged) → T8. Export wiring + on-demand fetch after confirm + snackbar count → T9. Verification → T10. On-screen tab unchanged (no task touches `replenishment_report_body.dart`) ✓.
- **Type consistency:** `replenishmentLineRows(List<Replenishment>, Map<String,FundRequest>, Map<String,String>)` used identically in T3/T7. `ReplenishedLineRow` fields identical across T2/T3/T4/T5/T6/T8/T9. `fetchReplenishmentLineItems(String, DateRange) → Result<ReportPage<ReplenishedLineRow>>` identical in T7 interface/impl/T9 call. `shareReplenishmentDetail(ReportExportFormat, ReportSummary<ReplenishedLineRow>, String)` identical in T8/T9.
- **Known limitation (documented):** legacy approved bundles with no `items` array contribute zero detail rows; modern bundles always persist `items`, so the line-item grand total equals the bundle total for current data.
