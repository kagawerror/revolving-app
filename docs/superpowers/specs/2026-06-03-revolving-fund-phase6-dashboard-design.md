# Revolving Fund App — Phase 6 Design Spec (Real-time Monitoring Dashboard)

- **Date:** 2026-06-03
- **Status:** Approved (extends Phases 1–5; final phase)

## 1. Purpose

An in-app, real-time **monitoring dashboard** so managers/CEO/incharge can see fund health at a
glance: total budget vs available vs disbursed, per-fund utilization, low/replenishing funds, pending
work, and recent activity — all updating live via Firestore streams.

## 2. Decisions (stated; no blocking questions for the final phase)

| Decision | Choice |
|---|---|
| Surface | In-app screen (mobile), reached from a dashboard icon on each role's home |
| Scope | The signed-in user's **company** (`currentUser.companyId`). Admin multi-company view deferred. |
| Audience | Incharge, approvers (superior/manager/CEO), and admin — read-only monitoring |
| Real-time | Firestore `.snapshots()` streams (no polling) |
| Aggregates | Derived from fund balances (disbursed = ceiling − available); pure, unit-tested |

## 3. Content

1. **Summary cards (company aggregate):**
   - Total budget (Σ fund ceilings), Total available (Σ available), Total disbursed (Σ ceiling−available).
   - Utilization % = disbursed / budget.
   - Fund count, low-balance fund count, replenishing fund count.
   - Pending requests (status `pendingAck`) count, pending replenishments (status `submitted`) count.
2. **Per-fund list:** each fund with a utilization progress bar (available / ceiling), a status chip
   (active / low / replenishing), the available and ceiling amounts, and the low-balance threshold.
3. **Recent activity feed:** the latest N (15) requests for the company, newest first — beneficiary,
   amount, status, purpose.

## 4. Architecture

- `features/dashboard/domain/dashboard_summary.dart` — `FundTotals` value object + a pure
  `computeFundTotals(List<Fund>)` (budget/available/disbursed via `Money`, low/replenishing counts);
  and a `DashboardSummary` combining `FundTotals` with the two pending counts. **Unit-tested.**
- `features/dashboard/presentation/dashboard_providers.dart` — composes existing streams
  (company funds, pending requests, pending replenishments) + a new recent-requests stream into a
  `dashboardSummaryProvider` and a `recentRequestsProvider`.
- `features/dashboard/presentation/dashboard_screen.dart` — the read-only UI.
- `RequestRepository.watchRecentByCompany(companyId, limit)` — new stream
  (`where companyId == … orderBy createdAt desc limit N`); requires a composite index.
- Entry points: a dashboard `IconButton` on the incharge/approver/admin home AppBars → push
  `DashboardScreen` (MaterialPageRoute, consistent with the alerts/detail screens).

## 5. Data / indexes

No new collections. New composite index: `requests (companyId ASC, createdAt DESC)` for the recent
feed. (The aggregate/per-fund data reuses the existing `funds` and status-filtered streams.)

## 6. Security

Read-only; all reads are already gated by the existing `sameCompany` rules on `funds`, `requests`,
`replenishments`. No rule changes.

## 7. Out of scope

- Admin cross-company / multi-company aggregation and company picker.
- Historical charts / time-series, CSV export, date-range filters.
- Per-fund drill-down screens beyond the existing request/replenishment screens.
