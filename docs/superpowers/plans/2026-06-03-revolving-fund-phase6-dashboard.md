# Revolving Fund App — Phase 6 Implementation Plan (Real-time Dashboard)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A read-only, real-time monitoring dashboard (company-scoped) showing aggregate budget/available/disbursed + utilization, per-fund utilization, pending-work counts, and a recent-activity feed — live via Firestore streams.

**Architecture:** New `features/dashboard/`. A pure `computeFundTotals(List<Fund>)` (unit-tested) drives the aggregates; providers compose existing streams (company funds, pending requests, pending replenishments) + a new recent-requests stream; one `DashboardScreen`. Reached from a dashboard icon on each home AppBar.

**Reference spec:** `docs/superpowers/specs/2026-06-03-revolving-fund-phase6-dashboard-design.md`

**Builds on:** `Money`, `Fund`/`FundStatus`, `FundRequest`/`RequestStatus`, `companyFundsProvider` (companies/presentation/admin_providers.dart, family by companyId), `pendingRequestsProvider` (requests/presentation/approver_inbox_providers.dart — pendingAck for the user's company), `pendingReplenishmentsProvider` (replenishment/presentation/replenishment_providers.dart — submitted for company), `requestRepositoryProvider`, `currentUserProvider`, `firestore.indexes.json`.

---

## File Structure (Phase 6)

```
lib/features/dashboard/
  domain/dashboard_summary.dart            # FundTotals + computeFundTotals + DashboardSummary
  presentation/dashboard_providers.dart
  presentation/dashboard_screen.dart
lib/features/requests/domain/request_repository.dart        # + watchRecentByCompany
lib/features/requests/data/firestore_request_repository.dart # impl
lib/features/{companies,requests}/presentation/*_home_screen.dart  # dashboard entry icon
firestore.indexes.json                     # requests (companyId, createdAt desc)
```

---

### Task 40: `FundTotals` + `computeFundTotals` + `DashboardSummary` (TDD)

**Files:** Create `lib/features/dashboard/domain/dashboard_summary.dart`; Test `test/features/dashboard/domain/dashboard_summary_test.dart`.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/dashboard/domain/dashboard_summary.dart';

Fund _fund(int budget, int available, FundStatus status) => Fund(
      id: 'f', companyId: 'c1', name: 'F',
      originalBudget: Money.fromCentavos(budget),
      availableBalance: Money.fromCentavos(available),
      lowBalanceThresholdPct: 3, status: status);

void main() {
  test('empty funds → zero totals, zero utilization', () {
    final t = computeFundTotals(const []);
    expect(t.totalBudget, Money.zero);
    expect(t.totalAvailable, Money.zero);
    expect(t.totalDisbursed, Money.zero);
    expect(t.utilization, 0.0);
    expect(t.fundCount, 0);
  });

  test('sums budget/available/disbursed and counts statuses', () {
    final t = computeFundTotals([
      _fund(10000000, 4000000, FundStatus.active),    // disbursed 6,000,000
      _fund(5000000, 100000, FundStatus.low),          // disbursed 4,900,000
      _fund(2000000, 2000000, FundStatus.replenishing) // disbursed 0
    ]);
    expect(t.totalBudget, Money.fromCentavos(17000000));
    expect(t.totalAvailable, Money.fromCentavos(6100000));
    expect(t.totalDisbursed, Money.fromCentavos(10900000));
    expect(t.fundCount, 3);
    expect(t.lowFundCount, 1);
    expect(t.replenishingFundCount, 1);
    // utilization = 10,900,000 / 17,000,000
    expect(t.utilization, closeTo(0.6412, 0.0001));
  });
}
```

- [ ] **Step 2: Run → FAIL.** `flutter test test/features/dashboard/domain/dashboard_summary_test.dart`

- [ ] **Step 3: Implement** `dashboard_summary.dart`

```dart
import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';
import '../../companies/domain/fund.dart';

class FundTotals extends Equatable {
  final Money totalBudget;
  final Money totalAvailable;
  final int fundCount;
  final int lowFundCount;
  final int replenishingFundCount;

  const FundTotals({
    required this.totalBudget,
    required this.totalAvailable,
    required this.fundCount,
    required this.lowFundCount,
    required this.replenishingFundCount,
  });

  Money get totalDisbursed => totalBudget - totalAvailable;

  /// Fraction 0..1 of the budget that is currently disbursed.
  double get utilization =>
      totalBudget.centavos == 0 ? 0.0 : totalDisbursed.centavos / totalBudget.centavos;

  @override
  List<Object?> get props =>
      [totalBudget, totalAvailable, fundCount, lowFundCount, replenishingFundCount];
}

/// Pure aggregate over a company's funds. (available never exceeds budget, so the
/// disbursed subtraction is always >= 0.)
FundTotals computeFundTotals(List<Fund> funds) {
  var budget = Money.zero;
  var available = Money.zero;
  var low = 0;
  var replenishing = 0;
  for (final f in funds) {
    budget += f.originalBudget;
    available += f.availableBalance;
    if (f.status == FundStatus.low) low++;
    if (f.status == FundStatus.replenishing) replenishing++;
  }
  return FundTotals(
    totalBudget: budget,
    totalAvailable: available,
    fundCount: funds.length,
    lowFundCount: low,
    replenishingFundCount: replenishing,
  );
}

class DashboardSummary extends Equatable {
  final FundTotals totals;
  final int pendingRequestCount;
  final int pendingReplenishmentCount;

  const DashboardSummary({
    required this.totals,
    required this.pendingRequestCount,
    required this.pendingReplenishmentCount,
  });

  @override
  List<Object?> get props => [totals, pendingRequestCount, pendingReplenishmentCount];
}
```

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit** `feat(dashboard): FundTotals + computeFundTotals (TDD) + DashboardSummary`

---

### Task 41: Recent-requests stream + dashboard providers + index

**Files:** Modify `lib/features/requests/domain/request_repository.dart`, `lib/features/requests/data/firestore_request_repository.dart`, `firestore.indexes.json`; Create `lib/features/dashboard/presentation/dashboard_providers.dart`.

- [ ] **Step 1:** Add to the `RequestRepository` interface:

```dart
Stream<List<FundRequest>> watchRecentByCompany(String companyId, int limit);
```

- [ ] **Step 2:** Implement in `FirestoreRequestRepository`:

```dart
@override
Stream<List<FundRequest>> watchRecentByCompany(String companyId, int limit) => _requests
    .where('companyId', isEqualTo: companyId)
    .orderBy('createdAt', descending: true)
    .limit(limit)
    .snapshots()
    .map((s) => s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());
```

- [ ] **Step 3:** Append the composite index to `firestore.indexes.json` `indexes` array:

```json
{
  "collectionGroup": "requests",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "companyId", "order": "ASCENDING" },
    { "fieldPath": "createdAt", "order": "DESCENDING" }
  ]
}
```
Validate JSON (`python3 -m json.tool firestore.indexes.json`).

- [ ] **Step 4:** Create `dashboard_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_providers.dart';
import '../../replenishment/presentation/replenishment_providers.dart';
import '../../requests/domain/fund_request.dart';
import '../../requests/presentation/approver_inbox_providers.dart';
import '../../requests/presentation/request_providers.dart';
import '../domain/dashboard_summary.dart';

final recentRequestsProvider = StreamProvider<List<FundRequest>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref.watch(requestRepositoryProvider).watchRecentByCompany(user.companyId, 15);
});

final dashboardSummaryProvider = Provider<AsyncValue<DashboardSummary>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const AsyncValue.loading();
  final funds = ref.watch(companyFundsProvider(user.companyId));
  final pendingReq = ref.watch(pendingRequestsProvider).valueOrNull?.length ?? 0;
  final pendingRepl = ref.watch(pendingReplenishmentsProvider).valueOrNull?.length ?? 0;
  return funds.whenData((list) => DashboardSummary(
        totals: computeFundTotals(list),
        pendingRequestCount: pendingReq,
        pendingReplenishmentCount: pendingRepl,
      ));
});
```

- [ ] **Step 5:** `flutter analyze && flutter test` (green; existing tests unaffected). **Commit** `feat(dashboard): recent-requests stream + dashboard providers + index`

---

### Task 42: `DashboardScreen`

**Files:** Create `lib/features/dashboard/presentation/dashboard_screen.dart`.

- [ ] **Step 1: Implement**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/fund.dart';
import '../../companies/presentation/admin_providers.dart';
import 'dashboard_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final funds = user == null
        ? const AsyncValue<List<Fund>>.loading()
        : ref.watch(companyFundsProvider(user.companyId));
    final recent = ref.watch(recentRequestsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (s) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SummaryGrid(summary: s),
            const SizedBox(height: 24),
            Text('Funds', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            funds.maybeWhen(
              data: (list) => Column(
                children: [for (final f in list) _FundUtilizationTile(fund: f)],
              ),
              orElse: () => const LinearProgressIndicator(),
            ),
            const SizedBox(height: 24),
            Text('Recent activity', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            recent.maybeWhen(
              data: (list) => list.isEmpty
                  ? const Text('No recent requests')
                  : Column(children: [
                      for (final r in list)
                        ListTile(
                          dense: true,
                          title: Text('${r.beneficiaryName} — ${r.amount.format()}'),
                          subtitle: Text('${r.purpose} · ${r.status.name}'),
                        ),
                    ]),
              orElse: () => const LinearProgressIndicator(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final DashboardSummary summary;
  const _SummaryGrid({required this.summary});

  @override
  Widget build(BuildContext context) {
    final t = summary.totals;
    final pct = (t.utilization * 100).toStringAsFixed(1);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatCard(label: 'Total budget', value: t.totalBudget.format()),
        _StatCard(label: 'Available', value: t.totalAvailable.format()),
        _StatCard(label: 'Disbursed', value: t.totalDisbursed.format()),
        _StatCard(label: 'Utilization', value: '$pct%'),
        _StatCard(label: 'Funds', value: '${t.fundCount}'),
        _StatCard(
            label: 'Low / replenishing',
            value: '${t.lowFundCount} / ${t.replenishingFundCount}'),
        _StatCard(label: 'Pending requests', value: '${summary.pendingRequestCount}'),
        _StatCard(
            label: 'Pending replenishments',
            value: '${summary.pendingReplenishmentCount}'),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _FundUtilizationTile extends StatelessWidget {
  final Fund fund;
  const _FundUtilizationTile({required this.fund});

  @override
  Widget build(BuildContext context) {
    final ceiling = fund.originalBudget.centavos;
    final fraction =
        ceiling == 0 ? 0.0 : fund.availableBalance.centavos / ceiling;
    final scheme = Theme.of(context).colorScheme;
    final color = switch (fund.status) {
      FundStatus.low => scheme.error,
      FundStatus.replenishing => scheme.tertiary,
      FundStatus.active => scheme.primary,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(fund.name)),
              Chip(
                label: Text(fund.status.name),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${fund.availableBalance.format()} of ${fund.originalBudget.format()} '
            '(alert ≤ ${fund.lowBalanceThreshold.format()})',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
```

> If `ColorScheme.surfaceContainerHighest` isn't available in the installed Flutter, use `scheme.surfaceVariant` instead — pick whichever the analyzer accepts.

- [ ] **Step 2:** `flutter analyze`. **Commit** `feat(dashboard): real-time DashboardScreen UI`

---

### Task 43: Dashboard entry points on the home screens

**Files:** Modify `lib/features/companies/presentation/admin_home_screen.dart`, `lib/features/requests/presentation/incharge_home_screen.dart`, `lib/features/requests/presentation/approver_home_screen.dart`.

- [ ] **Step 1:** In each home screen's AppBar `actions:`, add a dashboard button BEFORE the existing alerts bell / logout:

```dart
IconButton(
  icon: const Icon(Icons.dashboard_outlined),
  tooltip: 'Dashboard',
  onPressed: () => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DashboardScreen())),
),
```
Add `import '../../dashboard/presentation/dashboard_screen.dart';` to each. (Admin home is under `companies/`, so the relative path is `../../dashboard/presentation/dashboard_screen.dart`; verify the path from each file.)

- [ ] **Step 2:** `flutter analyze && flutter test` (green). **Commit** `feat(dashboard): dashboard entry points on home screens`

---

## Manual Verification (end of Phase 6)

1. Sign in (any role) → tap the dashboard icon → see total budget/available/disbursed, utilization %, fund/low/replenishing counts, and pending-work counts.
2. Release a request → the disbursed total + the fund's utilization bar update live; if it crosses the threshold, the low-fund count increments and the bar turns red.
3. Approve a replenishment → available jumps back to the ceiling, utilization drops, the fund returns to active live.
4. Recent activity lists the latest 15 requests newest-first.

## Self-Review (against the Phase 6 spec)

- **Coverage:** aggregate summary (budget/available/disbursed/utilization, fund/low/replenishing counts, pending counts) ✓; per-fund utilization bars + status ✓; recent activity feed ✓; live via streams ✓; company-scoped + entry points for all roles ✓; index for the recent feed ✓.
- **Deferred (per spec):** admin multi-company view, charts/time-series/export, drill-downs.
- **Testability:** `computeFundTotals` is unit-tested (the aggregate logic); the screen/providers are stream/UI-bound (manual verification).
- **Type consistency:** `FundTotals`/`computeFundTotals`/`DashboardSummary`, `watchRecentByCompany`, `dashboardSummaryProvider`/`recentRequestsProvider` used consistently.
- **No money math outside Money:** totals accumulate via `Money`; utilization is the only ratio (double), used for display/progress only.
