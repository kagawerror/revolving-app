import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/fund.dart';
import '../../companies/presentation/admin_providers.dart';
import '../../replenishment/presentation/replenishment_providers.dart';
import '../../requests/presentation/approver_inbox_providers.dart';
import '../domain/dashboard_summary.dart';
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
            recent.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const Text('Could not load recent activity'),
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
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends ConsumerWidget {
  final DashboardSummary summary;
  const _SummaryGrid({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = summary.totals;
    final pct = (t.utilization * 100).toStringAsFixed(1);
    final pendingReq = ref.watch(pendingRequestsProvider).valueOrNull;
    final pendingRepl = ref.watch(pendingReplenishmentsProvider).valueOrNull;
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
        _StatCard(
            label: 'Pending requests',
            value: pendingReq?.length.toString() ?? '…'),
        _StatCard(
            label: 'Pending replenishments',
            value: pendingRepl?.length.toString() ?? '…'),
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
