# Surface fund "Adjustment" and roll it into Total budget

**Date:** 2026-06-16
**Branch:** feat/forced-password-change (current)
**Status:** Approved design — pending implementation plan

## Problem

The dashboard hero card shows **Available balance** (`fund.availableBalance`) and
**Total budget** (`fund.originalBudget`) as two independent figures. The
admin/CEO "add cash" action (`adjustBalance`) increases the available balance
**without** touching the budget, so a fund can show a balance well above its
budget (e.g. ₱1,975,000 available vs ₱1,000,000 budget) with no on-screen
explanation. Users cannot see that a +₱975,000 adjustment is the cause.

**Goal:** display the accumulated balance adjustment, and present a **Total
budget that includes the adjustment** (effective budget = original + adjustment).

## Key facts about the existing system

- A `Fund` stores only `originalBudgetCentavos` and `availableBalanceCentavos`.
  There is **no stored running adjustment total** — adjustments are written only
  to the per-fund `history` subcollection.
- **Two** adjustment paths exist:
  - `adjustBudget` — changes budget **and** balance by the same delta (no surplus
    created). Must NOT count toward "adjustment".
  - `adjustBalance` — changes balance **only** (budget fixed). This is the path
    that creates `available > budget`. This is the figure we surface.
- `available − budget` is **not** a reliable proxy for "adjustment": once cash is
  released it becomes "adjustment minus disbursed". It equals the adjustment only
  while nothing has been disbursed (which is true for the screenshot fund today).
- Money is integer centavos throughout (`Money`). Money mutations run in
  Firestore transactions that re-read + re-validate; legal transitions are
  re-encoded in `firestore.rules`.
- `BalanceHeroCard` has exactly **one** caller (`dashboard_body.dart`).

## Decisions (confirmed with user)

1. **Source of the adjustment figure:** a persistent, signed running total stored
   on the fund (`adjustmentsCentavos`), not derived and not summed from history.
2. **Backfill of existing funds:** seed `adjustmentsCentavos = max(0, available −
   originalBudget)` once. Exact for undisbursed funds; slightly under-counts funds
   that have already released cash.
3. **Hero card layout:** three-row breakdown — Original budget / Adjustment /
   Total budget.
4. **Backfill execution:** run via Firebase MCP, with a dry-run of the planned
   writes shown for approval before execution.

## Design

### 1. Domain — `Fund` (`lib/features/companies/domain/fund.dart`)

Add one field:

```dart
final int adjustmentsCentavos; // signed; accumulates adjustBalance deltas only
```

- `fromMap`: `adjustmentsCentavos: (m['adjustmentsCentavos'] ?? 0) as int` (back-
  compatible default for un-migrated docs).
- `toCreateMap`: write `'adjustmentsCentavos': adjustmentsCentavos` (new funds
  start at 0).
- Add to `props`.
- Derived getter (single source of truth for the math):

```dart
// adjustmentsCentavos is signed and CAN be negative (net deductions); it is
// therefore kept as a raw int, NOT wrapped in Money — Money.fromCentavos throws
// on negatives. effectiveBudget is always >= 0 (you cannot deduct more cash than
// exists), so wrapping the sum in Money is safe.
Money get effectiveBudget =>
    Money.fromCentavos(originalBudget.centavos + adjustmentsCentavos);
```

The signed adjustment is rendered with a small abs-based formatting helper in the
presentation layer (see §5) — never by passing a negative to `Money.fromCentavos`.

`originalBudget`, `lowBalanceThreshold`, and `isLow` are unchanged — the low
threshold stays derived from the **original** budget (an adjustment must not move
the low-balance line, matching `computeFundAdjustment`).

### 2. Repository (`firestore_fund_repository.dart`)

- `adjustBalance`: add to the existing `tx.update`:
  `'adjustmentsCentavos': FieldValue.increment(adj.signedDeltaCentavos)`.
  No new transaction, no new read — rides the existing re-read/re-validate path.
- `adjustBudget`: **unchanged** (does not accumulate adjustment).
- `create`: persists `adjustmentsCentavos: 0` via `toCreateMap`.

### 3. Firestore rules (`firestore.rules`)

Permit `adjustmentsCentavos` on fund create/update for the roles already allowed
to adjust balance (admin/CEO). Without this the client write is rejected
server-side. Re-validate that the field is an int.

### 4. Aggregation — `FundTotals` (`dashboard_summary.dart`)

- Add `final int totalAdjustmentsCentavos;` to `FundTotals` (signed; + constructor
  + props). Kept as a raw int, not Money, because it can be negative.
- `computeFundTotals`: sum `f.adjustmentsCentavos`.
- New getter: `Money get effectiveBudget =>
  Money.fromCentavos(totalBudget.centavos + totalAdjustmentsCentavos);`
- Re-base `totalDisbursed` on `effectiveBudget − totalAvailable`. With adjustments
  now in the effective budget, available can no longer legitimately exceed it, so
  the `clamp` becomes a pure safety net (kept, but documented as such).
- `utilization`: `totalDisbursed / effectiveBudget` (guard `== 0`).

### 5. UI

- **`BalanceHeroCard`** (`lib/core/widgets/balance_hero_card.dart`): extend to
  render an optional ordered list of secondary rows (`label`, `amount`, optional
  emphasis flag) instead of a single secondary row. Keep the existing
  single-secondary API working, or migrate the one caller. The widget still does
  **no money logic** — all strings pre-formatted by the caller.
- **`dashboard_body.dart`**: build three rows:
  - `Original budget` → `t.totalBudget.format()`
  - `Adjustment` → signed format, e.g. `+₱975,000.00` (or `−…`)
  - `Total budget` → `t.effectiveBudget.format()` (emphasised)
  - `Available balance` (primary) unchanged.

### 6. One-time backfill (Firebase MCP)

For each fund document in the `funds` collection:
`adjustmentsCentavos = max(0, availableBalanceCentavos − originalBudgetCentavos)`.
Produce a dry-run table (fund id, name, available, budget, computed seed) for user
approval, then apply with `firestore_update_document` per fund. Funds that already
have a non-zero `adjustmentsCentavos` are skipped (idempotent re-run safe).

## Testing

- **Pure/domain:** `Fund.adjustments` / `effectiveBudget`; `fromMap` default when
  field absent; `computeFundTotals` sums adjustments and `effectiveBudget` math.
- **Data (`FakeFirebaseFirestore`):** `adjustBalance` increments
  `adjustmentsCentavos` by the signed delta; `adjustBudget` leaves it unchanged;
  a deduct (negative delta) decrements it.
- **Widget (optional):** hero card renders three rows with correct labels/order.

## Out of scope (YAGNI)

- No per-fund adjustment history UI (already in `history`).
- No change to `adjustBudget` semantics.
- No retroactive recomputation from history (backfill is the simple seed).
