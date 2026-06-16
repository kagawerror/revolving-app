# Fund Adjustment in Total Budget — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track each fund's accumulated balance adjustment as a stored signed field, surface it on the dashboard, and present a Total budget that includes it (effective budget = original + adjustment).

**Architecture:** Add a signed `adjustmentsCentavos` int to `Fund`, incremented atomically inside the existing `adjustBalance` transaction (never `adjustBudget`). Aggregate it in `FundTotals` and expose an `effectiveBudget`. Extend `BalanceHeroCard` to render a three-row breakdown (Original / Adjustment / Total). Finally, a one-time Firebase-MCP backfill seeds existing funds.

**Tech Stack:** Flutter/Dart, Riverpod, Firebase (Firestore), `flutter_test` + `fake_cloud_firestore`. Money is integer centavos via `Money`.

**Reference spec:** `docs/superpowers/specs/2026-06-16-fund-adjustment-in-total-budget-design.md`

**Key constraints (do not violate):**
- Money is integer centavos. `Money.fromCentavos` **throws on negative** — never pass it a negative. The signed adjustment stays a raw `int`; only its absolute value is wrapped in `Money` for display.
- Money mutations run in Firestore transactions that re-read + re-validate. Legal writes are re-encoded in `firestore.rules` — change both or the write is rejected server-side.
- `adjustBudget` must NOT change `adjustmentsCentavos`; only `adjustBalance` does.

---

## File Structure

- **Modify** `lib/features/companies/domain/fund.dart` — add signed `adjustmentsCentavos` field (default 0), `effectiveBudget` getter, map (de)serialization, props.
- **Modify** `lib/features/companies/data/firestore_fund_repository.dart` — increment `adjustmentsCentavos` inside `adjustBalance`'s existing `tx.update`.
- **Modify** `firestore.rules` — allow `adjustmentsCentavos` in the availability-only (Fund Adjustment) update diff.
- **Modify** `lib/features/dashboard/domain/dashboard_summary.dart` — add `totalAdjustmentsCentavos`, `effectiveBudget`; re-base `totalDisbursed`/`utilization` on effective budget.
- **Modify** `lib/core/widgets/balance_hero_card.dart` — optional multi-row secondary section.
- **Modify** `lib/features/dashboard/presentation/dashboard_body.dart` — build the three rows + signed-money helper.
- **Tests:** `test/features/companies/data/fund_repository_test.dart`, `test/features/dashboard/domain/dashboard_summary_test.dart`, and a new `test/features/companies/domain/fund_test.dart`.
- **Backfill:** Firebase MCP (Task 7) — no code file.

---

## Task 1: `Fund` gains a signed `adjustmentsCentavos` field

**Files:**
- Modify: `lib/features/companies/domain/fund.dart`
- Test: `test/features/companies/domain/fund_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/features/companies/domain/fund_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/fund.dart';

void main() {
  Fund base({int adj = 0}) => Fund(
        id: 'f1',
        companyId: 'c1',
        name: 'Petty Cash',
        originalBudget: Money.fromCentavos(1000000),
        availableBalance: Money.fromCentavos(1975000),
        lowBalanceThresholdPct: 3,
        status: FundStatus.active,
        adjustmentsCentavos: adj,
      );

  test('adjustmentsCentavos defaults to 0 when omitted by fromMap', () {
    final f = Fund.fromMap('f1', {
      'companyId': 'c1',
      'name': 'Petty Cash',
      'originalBudgetCentavos': 1000000,
      'availableBalanceCentavos': 1975000,
      'lowBalanceThresholdPct': 3,
      'status': 'active',
    });
    expect(f.adjustmentsCentavos, 0);
    expect(f.effectiveBudget, Money.fromCentavos(1000000));
  });

  test('fromMap reads adjustmentsCentavos and effectiveBudget adds it', () {
    final f = Fund.fromMap('f1', {
      'companyId': 'c1',
      'name': 'Petty Cash',
      'originalBudgetCentavos': 1000000,
      'availableBalanceCentavos': 1975000,
      'lowBalanceThresholdPct': 3,
      'status': 'active',
      'adjustmentsCentavos': 975000,
    });
    expect(f.adjustmentsCentavos, 975000);
    expect(f.effectiveBudget, Money.fromCentavos(1975000));
  });

  test('effectiveBudget handles a net-negative adjustment without throwing', () {
    final f = base(adj: -200000); // 1,000,000 - 200,000
    expect(f.effectiveBudget, Money.fromCentavos(800000));
  });

  test('toCreateMap persists adjustmentsCentavos', () {
    expect(base(adj: 500000).toCreateMap()['adjustmentsCentavos'], 500000);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/companies/domain/fund_test.dart`
Expected: FAIL — `Fund` has no `adjustmentsCentavos`/`effectiveBudget`.

- [ ] **Step 3: Modify `Fund`**

In `lib/features/companies/domain/fund.dart`:

Add the field to the class (after `status`):

```dart
  final FundStatus status;

  /// Signed running total of availability-only adjustments (the admin/CEO
  /// "add/deduct cash" path). CAN be negative. Kept as a raw int because
  /// `Money.fromCentavos` rejects negatives. Budget edits (`adjustBudget`) do
  /// NOT accumulate here.
  final int adjustmentsCentavos;
```

Add to the constructor with a back-compatible default:

```dart
    required this.status,
    this.adjustmentsCentavos = 0,
  });
```

Add the getter (next to `lowBalanceThreshold`):

```dart
  /// Budget including accumulated adjustments — the "Total budget" shown to
  /// users. Always >= 0 (you cannot deduct more cash than exists).
  Money get effectiveBudget =>
      Money.fromCentavos(originalBudget.centavos + adjustmentsCentavos);
```

In `fromMap`, add the field (after `status:`):

```dart
        status: FundStatus.fromName(m['status'] as String?),
        adjustmentsCentavos: (m['adjustmentsCentavos'] ?? 0) as int,
      );
```

In `toCreateMap`, add (after `'status': status.name,`):

```dart
        'status': status.name,
        'adjustmentsCentavos': adjustmentsCentavos,
```

Add to `props`:

```dart
  List<Object?> get props => [
        id, companyId, name, originalBudget, availableBalance,
        lowBalanceThresholdPct, status, adjustmentsCentavos,
      ];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/companies/domain/fund_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/companies/domain/fund.dart test/features/companies/domain/fund_test.dart
git commit -m "feat(funds): add signed adjustmentsCentavos + effectiveBudget to Fund"
```

---

## Task 2: `FundTotals` aggregates adjustments and exposes `effectiveBudget`

**Files:**
- Modify: `lib/features/dashboard/domain/dashboard_summary.dart`
- Test: `test/features/dashboard/domain/dashboard_summary_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/features/dashboard/domain/dashboard_summary_test.dart`, inside `main()`. Update the local `_fund` helper at the top of that file to accept adjustments:

```dart
Fund _fund(int budget, int available, FundStatus status, {int adj = 0}) => Fund(
      id: 'f', companyId: 'c1', name: 'F',
      originalBudget: Money.fromCentavos(budget),
      availableBalance: Money.fromCentavos(available),
      lowBalanceThresholdPct: 3, status: status,
      adjustmentsCentavos: adj);
```

Then add these tests:

```dart
  test('sums adjustments and effectiveBudget = budget + adjustments', () {
    final t = computeFundTotals([
      _fund(1000000, 1975000, FundStatus.active, adj: 975000),
      _fund(2000000, 2000000, FundStatus.active, adj: 0),
    ]);
    expect(t.totalBudget, Money.fromCentavos(3000000));
    expect(t.totalAdjustmentsCentavos, 975000);
    expect(t.effectiveBudget, Money.fromCentavos(3975000));
    // available (3,975,000) == effective budget → nothing disbursed.
    expect(t.totalDisbursed, Money.zero);
    expect(t.utilization, 0.0);
  });

  test('disbursed/utilization are based on the effective budget', () {
    // effective = 1,000,000 + 500,000 = 1,500,000; available 900,000.
    final t = computeFundTotals([
      _fund(1000000, 900000, FundStatus.active, adj: 500000),
    ]);
    expect(t.effectiveBudget, Money.fromCentavos(1500000));
    expect(t.totalDisbursed, Money.fromCentavos(600000));
    expect(t.utilization, closeTo(0.4, 0.0001));
  });

  test('net-negative adjustments lower the effective budget', () {
    final t = computeFundTotals([
      _fund(1000000, 800000, FundStatus.active, adj: -200000),
    ]);
    expect(t.totalAdjustmentsCentavos, -200000);
    expect(t.effectiveBudget, Money.fromCentavos(800000));
    expect(t.totalDisbursed, Money.zero); // available == effective
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/dashboard/domain/dashboard_summary_test.dart`
Expected: FAIL — `totalAdjustmentsCentavos`/`effectiveBudget` undefined.

- [ ] **Step 3: Modify `dashboard_summary.dart`**

Add the field to `FundTotals` (after `replenishingFundCount`):

```dart
  final int replenishingFundCount;
  final int totalAdjustmentsCentavos;
```

Add to the constructor:

```dart
    required this.replenishingFundCount,
    required this.totalAdjustmentsCentavos,
  });
```

Add the `effectiveBudget` getter and re-base disbursed/utilization on it (replace the existing `totalDisbursed` and `utilization` getters):

```dart
  /// Budget including all accumulated adjustments — the "Total budget" shown.
  Money get effectiveBudget =>
      Money.fromCentavos(totalBudget.centavos + totalAdjustmentsCentavos);

  /// Cash paid out of the funds (effective budget minus what's still available).
  /// Clamped at >= 0 as a safety net; with adjustments folded into the effective
  /// budget, available should never legitimately exceed it.
  Money get totalDisbursed => Money.fromCentavos(
      (effectiveBudget.centavos - totalAvailable.centavos).clamp(0, 1 << 62));

  /// Fraction 0..1 of the effective budget that is currently disbursed.
  double get utilization => effectiveBudget.centavos == 0
      ? 0.0
      : totalDisbursed.centavos / effectiveBudget.centavos;
```

Add to `props`:

```dart
  List<Object?> get props => [
        totalBudget, totalAvailable, fundCount, lowFundCount,
        replenishingFundCount, totalAdjustmentsCentavos,
      ];
```

In `computeFundTotals`, accumulate and pass the new field:

```dart
  var budget = Money.zero;
  var available = Money.zero;
  var adjustments = 0;
  var low = 0;
  var replenishing = 0;
  for (final f in funds) {
    budget += f.originalBudget;
    available += f.availableBalance;
    adjustments += f.adjustmentsCentavos;
    if (f.status == FundStatus.low) low++;
    if (f.status == FundStatus.replenishing) replenishing++;
  }
  return FundTotals(
    totalBudget: budget,
    totalAvailable: available,
    fundCount: funds.length,
    lowFundCount: low,
    replenishingFundCount: replenishing,
    totalAdjustmentsCentavos: adjustments,
  );
```

- [ ] **Step 4: Run the full dashboard test file**

Run: `flutter test test/features/dashboard/domain/dashboard_summary_test.dart`
Expected: PASS (existing tests still green — `totalBudget`/`totalAvailable` unchanged; the old "available exceeds budget" regression test now has `adj` default 0 so effective == budget and the clamp still holds).

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/domain/dashboard_summary.dart test/features/dashboard/domain/dashboard_summary_test.dart
git commit -m "feat(dashboard): aggregate fund adjustments into effective budget"
```

---

## Task 3: `adjustBalance` increments `adjustmentsCentavos`; `adjustBudget` does not

**Files:**
- Modify: `lib/features/companies/data/firestore_fund_repository.dart:140-143`
- Test: `test/features/companies/data/fund_repository_test.dart`

- [ ] **Step 1: Write the failing tests**

In `test/features/companies/data/fund_repository_test.dart`, inside the `group('adjustBalance', ...)`, add:

```dart
    test('addition increments adjustmentsCentavos by the signed delta',
        () async {
      await seedFund(budget: 10000000, balance: 5000000);
      final repo = FirestoreFundRepository(db);
      await repo.adjustBalance(
        fundId: 'f1',
        signedDeltaCentavos: 2000000,
        reason: 'Cash injection',
        actorUid: 'ceo-1',
        actorRole: UserRole.ceo,
      );
      final data = (await db.collection('funds').doc('f1').get()).data()!;
      expect(data['adjustmentsCentavos'], 2000000);
    });

    test('deduction decrements adjustmentsCentavos (can go negative)', () async {
      await seedFund(budget: 10000000, balance: 5000000);
      final repo = FirestoreFundRepository(db);
      await repo.adjustBalance(
        fundId: 'f1',
        signedDeltaCentavos: -800000,
        reason: 'Spillage correction',
        actorUid: 'admin-1',
        actorRole: UserRole.admin,
      );
      final data = (await db.collection('funds').doc('f1').get()).data()!;
      expect(data['adjustmentsCentavos'], -800000);
    });
```

In the `group('adjustBudget', ...)` (find the existing group; if absent, add this test at top level after the adjustBalance group), add:

```dart
    test('adjustBudget does NOT touch adjustmentsCentavos', () async {
      await seedFund(budget: 10000000, balance: 5000000);
      final repo = FirestoreFundRepository(db);
      await repo.adjustBudget(
        fundId: 'f1',
        newBudget: Money.fromCentavos(12000000),
        actorUid: 'admin-1',
        note: 'Raise budget',
      );
      final data = (await db.collection('funds').doc('f1').get()).data()!;
      // seedFund never wrote the field; adjustBudget must not introduce it.
      expect(data.containsKey('adjustmentsCentavos'), isFalse);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/companies/data/fund_repository_test.dart`
Expected: FAIL — `adjustmentsCentavos` is not written by `adjustBalance`.

- [ ] **Step 3: Modify `adjustBalance`**

In `lib/features/companies/data/firestore_fund_repository.dart`, in the `adjustBalance` transaction, extend the existing `tx.update` (currently writes `availableBalanceCentavos` + `status`):

```dart
        tx.update(ref, {
          'availableBalanceCentavos': adj.newBalance.centavos,
          'status': adj.newStatus.name,
          'adjustmentsCentavos': FieldValue.increment(adj.signedDeltaCentavos),
        });
```

Leave `adjustBudget`'s `tx.update` unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/companies/data/fund_repository_test.dart`
Expected: PASS — including the existing adjustBalance/adjustBudget tests.

Note: `FieldValue.increment` on a doc with no `adjustmentsCentavos` starts from 0 (matches production Firestore and `fake_cloud_firestore`).

- [ ] **Step 5: Commit**

```bash
git add lib/features/companies/data/firestore_fund_repository.dart test/features/companies/data/fund_repository_test.dart
git commit -m "feat(funds): accumulate adjustmentsCentavos on balance adjustment"
```

---

## Task 4: Firestore rule allows `adjustmentsCentavos` in the adjustment diff

**Files:**
- Modify: `firestore.rules:135`

- [ ] **Step 1: Update the rule**

In `firestore.rules`, the Fund-Adjustment (availability-only) disjunct currently pins the diff to two keys. Add `adjustmentsCentavos`:

```
        || ((isAdmin() || isCeo())
          && request.resource.data.diff(resource.data).affectedKeys()
              .hasOnly(['availableBalanceCentavos', 'status', 'adjustmentsCentavos'])
          && request.resource.data.companyId == resource.data.companyId
          && request.resource.data.originalBudgetCentavos
              == resource.data.originalBudgetCentavos
          && request.resource.data.lowBalanceThresholdPct
              == resource.data.lowBalanceThresholdPct
          && request.resource.data.name == resource.data.name)
```

- [ ] **Step 2: Validate the rules compile**

Run: `firebase deploy --only firestore:rules --dry-run`
Expected: rules compile with no syntax error. (If `--dry-run` is unavailable, run `firebase emulators:exec --only firestore "true"` or rely on `firebase deploy` rejecting malformed rules.)

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "feat(rules): permit adjustmentsCentavos in fund-adjustment write"
```

> **Deploy reminder:** `firebase deploy --only firestore` must be run before the
> feature works against production (otherwise the new field write is rejected).
> Do this at release time, not necessarily during implementation.

---

## Task 5: `BalanceHeroCard` supports an ordered multi-row breakdown

**Files:**
- Modify: `lib/core/widgets/balance_hero_card.dart`

- [ ] **Step 1: Add a row model + optional `rows` param**

At the top of `lib/core/widgets/balance_hero_card.dart` (above the widget), add:

```dart
/// One label/amount line in the hero card's breakdown section. [emphasis] makes
/// the row stand out (used for the final "Total budget").
class HeroRow {
  const HeroRow(this.label, this.amount, {this.emphasis = false});
  final String label;
  final String amount;
  final bool emphasis;
}
```

Add an optional param to the constructor (keep the existing single-secondary API for back-compat):

```dart
    this.secondaryLabel,
    this.secondaryAmount,
    this.rows,
  });
```

```dart
  final String? secondaryLabel;
  final String? secondaryAmount;

  /// Optional multi-row breakdown shown beneath the primary amount. When
  /// provided, it takes precedence over [secondaryLabel]/[secondaryAmount].
  final List<HeroRow>? rows;
```

- [ ] **Step 2: Render the rows**

Replace the `if (hasSecondary) ...[` block's contents so it renders `rows` when present, else the single secondary row. Compute at the top of `build` (after `hasSecondary`):

```dart
    final multi = rows;
    final showMulti = multi != null && multi.isNotEmpty;
```

Then replace the trailing section with:

```dart
          if (showMulti) ...[
            const SizedBox(height: AppTokens.lg),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
            const SizedBox(height: AppTokens.md),
            for (var i = 0; i < multi.length; i++) ...[
              if (i > 0) const SizedBox(height: AppTokens.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    multi[i].label,
                    style: textTheme.bodyMedium?.copyWith(
                      color: multi[i].emphasis ? onGradient : onGradientMuted,
                      fontWeight: multi[i].emphasis ? FontWeight.w700 : null,
                    ),
                  ),
                  Text(
                    multi[i].amount,
                    style: (multi[i].emphasis
                            ? textTheme.titleMedium
                            : textTheme.bodyLarge)
                        ?.copyWith(
                      color: onGradient,
                      fontWeight:
                          multi[i].emphasis ? FontWeight.w800 : FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ] else if (hasSecondary) ...[
            // existing single-secondary block unchanged
            const SizedBox(height: AppTokens.lg),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
            const SizedBox(height: AppTokens.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(secLabel, style: textTheme.bodyMedium?.copyWith(color: onGradientMuted)),
                Text(
                  secAmount,
                  style: textTheme.titleMedium?.copyWith(
                    color: onGradient,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
```

> If `AppTokens.sm` does not exist, use `AppTokens.xs`. Verify against
> `lib/core/theme/app_tokens.dart` before writing.

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/core/widgets/balance_hero_card.dart`
Expected: No issues. (`secLabel`/`secAmount`/`hasSecondary` remain referenced by the `else if`.)

- [ ] **Step 4: Commit**

```bash
git add lib/core/widgets/balance_hero_card.dart
git commit -m "feat(ui): BalanceHeroCard supports a multi-row breakdown"
```

---

## Task 6: Dashboard renders Original / Adjustment / Total breakdown

**Files:**
- Modify: `lib/features/dashboard/presentation/dashboard_body.dart:84-90`

- [ ] **Step 1: Add a signed-money helper**

In `lib/features/dashboard/presentation/dashboard_body.dart`, add a top-level helper (above the widget that builds the hero card):

```dart
/// Formats a signed centavo amount as currency with an explicit sign, e.g.
/// `+₱975,000.00` / `−₱200,000.00` / `₱0.00`. Avoids passing a negative to
/// `Money.fromCentavos` (which throws).
String _signedMoney(int centavos) {
  if (centavos == 0) return Money.zero.format();
  final sign = centavos > 0 ? '+' : '−'; // U+2212 minus
  return '$sign${Money.fromCentavos(centavos.abs()).format()}';
}
```

Ensure `Money` is imported (add `import '../../../core/money/money.dart';` if not already present).

- [ ] **Step 2: Build the three rows**

Replace the `BalanceHeroCard(...)` call (currently passing `secondaryLabel`/`secondaryAmount`) with:

```dart
    return BalanceHeroCard(
      seed: seed,
      primaryLabel: 'Available balance',
      primaryAmount: t.totalAvailable.format(),
      rows: [
        HeroRow('Original budget', t.totalBudget.format()),
        HeroRow('Adjustment', _signedMoney(t.totalAdjustmentsCentavos)),
        HeroRow('Total budget', t.effectiveBudget.format(), emphasis: true),
      ],
    ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.06, end: 0);
```

Add `HeroRow` to the existing `balance_hero_card.dart` import (same file already imported for `BalanceHeroCard`).

- [ ] **Step 3: Verify analyze + full test suite**

Run: `flutter analyze`
Expected: No issues.

Run: `flutter test`
Expected: All pass.

- [ ] **Step 4: Commit**

```bash
git add lib/features/dashboard/presentation/dashboard_body.dart
git commit -m "feat(dashboard): show Original/Adjustment/Total budget breakdown"
```

---

## Task 7: One-time backfill of existing funds (Firebase MCP)

> Operational, not TDD. Run AFTER Tasks 1–4 are merged and `firebase deploy
> --only firestore` has shipped the rule. Idempotent: funds already carrying a
> non-zero `adjustmentsCentavos` are skipped.

- [ ] **Step 1: List all funds (dry run)**

Use Firebase MCP `firestore_query_collection` (or `firestore_list_documents`) on
`funds`. For each fund collect: `id`, `name`, `originalBudgetCentavos`,
`availableBalanceCentavos`, existing `adjustmentsCentavos` (may be absent).

- [ ] **Step 2: Compute and present the seed table for approval**

For each fund:
`seed = max(0, availableBalanceCentavos − originalBudgetCentavos)`.
Skip funds where `adjustmentsCentavos` already exists and is non-zero.
Present a table (id, name, available, budget, computed seed, action) and get
explicit user go-ahead before any write.

- [ ] **Step 3: Apply**

For each non-skipped fund, `firestore_update_document` setting
`adjustmentsCentavos = seed`. Re-read one fund to confirm.

- [ ] **Step 4: Verify on device**

Open the dashboard: the screenshot fund should now read
`Original budget ₱1,000,000.00 / Adjustment +₱975,000.00 / Total budget
₱1,975,000.00`, with Available balance ₱1,975,000.00 and Disbursed ₱0.00.

---

## Final verification

- [ ] `flutter analyze` — no issues
- [ ] `flutter test` — all green
- [ ] `firebase deploy --only firestore` — rules + indexes shipped
- [ ] Backfill applied and dashboard verified on device
