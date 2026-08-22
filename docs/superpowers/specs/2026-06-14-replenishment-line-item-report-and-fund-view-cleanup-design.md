# Replenishment line-item report + incharge fund-view cleanup

**Date:** 2026-06-14
**Branch:** `feat/offline-first`
**Status:** Design — awaiting user review

## Problem

1. **Fund view clutter.** The incharge per-fund list ([`incharge_home_body.dart`](../../../lib/features/requests/presentation/incharge_home_body.dart)) renders *every* request returned by `watchByFund`, including fully-finished `replenished` and `rejected` ones. The custodian's active worklist keeps growing with items that need no further action.

2. **Replenishment report lacks line-item detail.** A reports feature already exists (`/reports`, two tabs: Released / Replenishments) and already exports **PDF / CSV / Excel**. But the Replenishments export is *bundle-level* — one row per approved replenishment (`Approved date · #requests · Total`, [`report_csv.dart:52`](../../../lib/features/reports/domain/report_csv.dart)). There is no way to export *which requests* were replenished (beneficiary, purpose, fund, per-request amount).

## Decisions (confirmed with user)

| Question | Decision |
|---|---|
| Part 1 — which statuses to hide from the fund view | `replenished` **and** `rejected` (display-only; docs untouched) |
| Part 2 — report detail level | Line-item per request |
| On-screen vs export | On-screen Replenishments tab **keeps the bundle summary**; only the **export** becomes line-item detail |
| Read-cost bound | Cap + truncation flag (reuse existing 500-row pattern) |
| When the join reads happen | Only on export, **after** the confirm dialog (cancel = zero reads) |

## Part 1 — Hide finished requests from the incharge fund view

**Scope:** display only. The request stays in Firestore, still appears in its detail screen and in reports.

**Change:**
- Add a pure predicate on the request domain — `bool get isActiveInFund` (or a free function) — defined as: status is **not** `replenished` and **not** `rejected`. One place, testable.
- In the fund section's list rendering ([`incharge_home_body.dart` ~line 321](../../../lib/features/requests/presentation/incharge_home_body.dart)), filter the `list` through this predicate before the `for (final r in list)` loop.
- The existing empty-state ("No requests yet") then naturally shows when a fund's only requests are finished.

**Testing:** unit test the predicate across all `RequestStatus` values (hidden set is exactly `{replenished, rejected}`).

## Part 2 — Line-item replenishment export

The Replenishments tab UI and its on-screen `ReportSummary<ReplenishmentRow>` are unchanged. A **separate, on-demand detail dataset** is fetched and built only when the user exports while on the Replenishments tab.

### Why a join (not a `requests where status==replenished` query)
A partially-replenished request stays `released`/`acknowledged` (not `replenished`) yet its installments *were* replenished. Only the approved **bundle** records what was actually credited and when. Driving the report from approved bundles captures partials correctly and dates each row by the approval the money posted on (`decidedAt`).

### Data model (domain)
New immutable row model `ReplenishedLineRow` (in [`report_models.dart`](../../../lib/features/reports/domain/report_models.dart)):

| Field | Source |
|---|---|
| `approvedDate` (DateTime) | `Replenishment.decidedAt` |
| `fundName` (String) | fund doc resolved by `Replenishment.fundId` |
| `beneficiaryName` (String) | request doc |
| `purpose` (String) | request doc |
| `amount` (Money) | `ReplenishmentItem.amount` (the installment credited in this bundle) |
| `isPartial` (bool) | `ReplenishmentItem.isPartial` |
| `remarks` (String) | `ReplenishmentItem.remarks` (partials only) |
| `replenishmentId` (String) | `Replenishment.id` |

Reuses the existing generic `ReportSummary<ReplenishedLineRow>` (rows + grandTotal + period + truncated). **Invariant:** the line-item grand total equals the bundle-level grand total for the same period.

### Pure builder (domain, the test seam)
`ReportSummary<ReplenishedLineRow> replenishmentLineRows(List<Replenishment> approved, Map<String,(name,purpose)> reqById, Map<String,String> fundNameById, ReportPeriod period, {required int cap})`
- One row per `(bundle, item)`; skips items whose request was not resolvable (defensive).
- Sorted by `approvedDate` desc, then fund, then beneficiary.
- Caps at `cap` rows, sets `truncated` when exceeded; `grandTotal` sums only the rows included (consistent with the existing released report's truncation semantics — surfaced to the user).

### Repository (data)
New method on `ReportRepository` / `FirestoreReportRepository`:
`Future<Result<ReportSummary<ReplenishedLineRow>>> fetchReplenishmentLineItems(String companyId, ReportPeriod period)`
1. Reuse the existing approved-replenishments query (composite index already deployed — **no new index, no deploy**).
2. Collect unique `requestId`s and `fundId`s across the bundles.
3. Resolve each via **single-doc `.get()`** (allowed by the `sameCompany` read rule — same pattern the replenishment repo already uses), in parallel with `Future.wait`, capped.
4. Call the pure `replenishmentLineRows` builder; return `Ok(summary)`.
5. Catch → `developer.log` (no PII/amounts) → `Err(UnexpectedFailure('Could not load the replenishment detail report.'))`.

### Per-format builders (domain)
Add detail builders mirroring the existing ones:
- `replenishmentDetailCsv(summary, periodLabel)` — header `Approved date,Fund,Beneficiary,Purpose,Type,Amount` + rows + `GRAND TOTAL`. Amounts via `moneyPesosBare`.
- `replenishmentDetailXlsx(summary, periodLabel)` — in [`report_xlsx.dart`](../../../lib/features/reports/domain/report_xlsx.dart).
- `replenishmentDetailPdf(summary, periodLabel)` — in [`report_pdf.dart`](../../../lib/features/reports/domain/report_pdf.dart).

### Wiring (presentation / service)
- The **Released** tab export path is untouched (still uses the in-memory summary).
- The **Replenishments** tab export path changes: after the format chooser + confirm, fetch `fetchReplenishmentLineItems(companyId, period)`, then build + share from the detail summary. The snackbar reports the actual **line-item** count; on failure, `context.showFailure`.
- The confirm dialog labels the kind "Replenishments (line-item detail)"; period + bundle count shown as today.
- `ReportShareService.shareReport` is extended to accept the detail dataset. Cleanest: add an optional dedicated entry `shareReplenishmentDetail(format, summary, periodLabel)` (avoids widening the `ReportKind` switch with a 3rd kind that has no on-screen tab), or add a `ReportKind.replenishmentDetail` branch. **Chosen: a dedicated `shareReplenishmentDetail` method** — keeps `ReportKind` mapped 1:1 to the visible tabs.

## Out of scope (YAGNI)
- No change to the on-screen Replenishments tab rows.
- No new Firestore indexes or rules changes.
- No change to the Released report.
- No "both summary + detail" toggle (user chose detail-only export).

## Testing plan
- **Part 1:** predicate unit test (hidden set == `{replenished, rejected}`).
- **Builder:** `replenishmentLineRows` — full + partial items, multi-bundle, sort order, grand-total == bundle total, cap/truncation, unresolved-request skip.
- **CSV/PDF/XLSX:** golden-ish assertions on the detail CSV header/rows/total (mirrors existing `report_csv` tests); PDF/XLSX smoke (bytes non-empty, parse).
- **Repository:** `fetchReplenishmentLineItems` against `FakeFirebaseFirestore` — joins requests+funds, applies period window, caps, returns `Err` on failure.
- Full `flutter test` + `flutter analyze` green before done.
