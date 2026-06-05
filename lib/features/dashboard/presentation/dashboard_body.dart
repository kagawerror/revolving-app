import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/balance_hero_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../companies/domain/fund.dart';
import '../../requests/domain/fund_request.dart';
import '../../requests/presentation/request_status_visual.dart';
import '../domain/dashboard_summary.dart';
import 'dashboard_providers.dart';

/// Maps a fund's lifecycle status to a consistent, color-coded pill tone +
/// label. The same status looks the same everywhere in the app.
({String label, StatusTone tone, IconData icon}) _fundStatusVisual(
    FundStatus status) {
  switch (status) {
    case FundStatus.active:
      return (label: 'Active', tone: StatusTone.success, icon: Icons.check_circle_rounded);
    case FundStatus.low:
      return (label: 'Low', tone: StatusTone.warning, icon: Icons.warning_amber_rounded);
    case FundStatus.replenishing:
      return (label: 'Replenishing', tone: StatusTone.info, icon: Icons.autorenew_rounded);
  }
}

/// Body of the dashboard tab: role-scoped balance hero, stats, funds, and recent
/// activity. Body-only — the [RoleShellScreen] owns the Scaffold and AppBar.
class DashboardBody extends ConsumerWidget {
  const DashboardBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);
    final funds = ref.watch(dashboardFundsProvider);
    final recent = ref.watch(recentRequestsProvider);

    return summary.when(
      loading: () => const _DashboardSkeleton(),
      error: (e, _) => _DashboardError(message: 'Error: $e'),
      data: (s) => ListView(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.lg,
          AppTokens.lg,
          AppTokens.lg,
          AppTokens.bottomNavContentInset,
        ),
        children: [
          _HeroSection(summary: s),
          const SizedBox(height: AppTokens.lg),
          _StatsSection(summary: s),
          const SectionHeader(title: 'Funds'),
          _FundsSection(funds: funds),
          const SectionHeader(title: 'Recent activity'),
          _RecentSection(recent: recent),
        ],
      ),
    );
  }
}

class _HeroSection extends ConsumerWidget {
  const _HeroSection({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = ref.watch(themeControllerProvider).seed;
    final t = summary.totals;
    return BalanceHeroCard(
      seed: seed,
      primaryLabel: 'Available balance',
      primaryAmount: t.totalAvailable.format(),
      secondaryLabel: 'Total budget',
      secondaryAmount: t.totalBudget.format(),
    ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.06, end: 0);
  }
}

class _StatsSection extends ConsumerWidget {
  const _StatsSection({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final t = summary.totals;
    final pct = (t.utilization * 100).toStringAsFixed(1);

    // Read the raw async providers directly (not the summary's settled counts)
    // so a still-loading count renders as a quiet em-dash rather than flashing
    // a misleading "0" before the real value arrives.
    final pendingReq = ref.watch(dashboardPendingRequestsProvider).valueOrNull;
    final pendingRepl =
        ref.watch(dashboardPendingReplenishmentsProvider).valueOrNull;

    final warnTone =
        StatusPill.colorsFor(StatusTone.warning, scheme).$2;
    final infoTone = scheme.primary;

    final cards = <Widget>[
      StatCard(
        label: 'Disbursed',
        value: t.totalDisbursed.format(),
        icon: Icons.trending_down_rounded,
        tone: scheme.tertiary,
      ),
      StatCard(
        label: 'Utilization',
        value: '$pct%',
        icon: Icons.donut_large_rounded,
        tone: infoTone,
      ),
      StatCard(
        label: 'Funds',
        value: '${t.fundCount}',
        icon: Icons.account_balance_wallet_rounded,
        tone: scheme.secondary,
      ),
      StatCard(
        label: 'Pending requests',
        value: pendingReq?.length.toString() ?? '—',
        icon: Icons.receipt_long_rounded,
        tone: warnTone,
      ),
      StatCard(
        label: 'Pending replenishments',
        value: pendingRepl?.length.toString() ?? '—',
        icon: Icons.replay_circle_filled_rounded,
        tone: warnTone,
      ),
      StatCard(
        label: 'Low / replenishing',
        value: '${t.lowFundCount} / ${t.replenishingFundCount}',
        icon: Icons.error_outline_rounded,
        tone: scheme.error,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Two columns on phones, three on wider screens.
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        final spacing = AppTokens.md;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(width: itemWidth, child: card),
          ],
        );
      },
    );
  }
}

class _FundsSection extends StatelessWidget {
  const _FundsSection({required this.funds});

  final AsyncValue<List<Fund>> funds;

  @override
  Widget build(BuildContext context) {
    return funds.when(
      loading: () => Column(
        children: [
          for (var i = 0; i < 2; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: AppTokens.md),
              child: _FundSkeletonCard(),
            ),
        ],
      ),
      error: (_, _) => const SurfaceCard(
        child: Text('Could not load funds'),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const SurfaceCard(
            child: Text('No funds yet'),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < list.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == list.length - 1 ? 0 : AppTokens.md,
                ),
                child: _FundCard(fund: list[i])
                    .animate()
                    .fadeIn(duration: 260.ms, delay: (60 * i).ms)
                    .slideX(begin: 0.04, end: 0),
              ),
          ],
        );
      },
    );
  }
}

class _FundCard extends ConsumerWidget {
  const _FundCard({required this.fund});

  final Fund fund;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final visual = _fundStatusVisual(fund.status);

    // Company label (overline above the fund name). The names map resolves to
    // empty while companies load, so we simply omit the line until it's ready —
    // never blocking the fund list. Falls back to 'Unknown company' once loaded
    // but missing (e.g. a deleted company).
    final names = ref.watch(companyNamesProvider);
    final companyName =
        names.isEmpty ? null : (names[fund.companyId] ?? 'Unknown company');

    final ceiling = fund.originalBudget.centavos;
    final fraction =
        ceiling == 0 ? 0.0 : (fund.availableBalance.centavos / ceiling).clamp(0.0, 1.0);

    // Progress bar color follows the status tone for an unmistakable read.
    final (_, barColor) = StatusPill.colorsFor(visual.tone, scheme);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (companyName != null)
                      Text(
                        companyName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    Text(
                      fund.name,
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.sm),
              StatusPill(
                label: visual.label,
                tone: visual.tone,
                icon: visual.icon,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.sm),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 10,
              color: barColor,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: AppTokens.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    children: [
                      TextSpan(
                        text: fund.availableBalance.format(),
                        style: textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      TextSpan(text: ' of ${fund.originalBudget.format()}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.sm),
              Text(
                'alert ≤ ${fund.lowBalanceThreshold.format()}',
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.recent});

  final AsyncValue<List<FundRequest>> recent;

  @override
  Widget build(BuildContext context) {
    return recent.when(
      loading: () => const SurfaceCard(child: SkeletonList(count: 4)),
      error: (_, _) => const SurfaceCard(
        child: Text('Could not load recent activity'),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const SurfaceCard(
            child: EmptyState(
              title: 'No recent activity',
              message: 'Requests and releases will show up here.',
            ),
          );
        }
        return SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.xs),
          child: Column(
            children: [
              for (var i = 0; i < list.length; i++)
                _RecentTile(request: list[i])
                    .animate()
                    .fadeIn(duration: 220.ms, delay: (40 * i).ms),
            ],
          ),
        );
      },
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.request});

  final FundRequest request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final visual = requestStatusVisual(request.status);

    return AppListTile(
      title: request.beneficiaryName,
      subtitle: request.purpose,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            request.amount.format(),
            style: textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppTokens.xs),
          StatusPill(label: visual.label, tone: visual.tone),
        ],
      ),
    );
  }
}

// --- Loading / error scaffolding ------------------------------------------

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppTokens.lg),
      children: [
        Skeleton.box(height: 132, radius: AppTokens.rCard),
        const SizedBox(height: AppTokens.lg),
        Wrap(
          spacing: AppTokens.md,
          runSpacing: AppTokens.md,
          children: [
            for (var i = 0; i < 4; i++)
              SizedBox(
                width: 150,
                child: Skeleton.box(height: 96, radius: AppTokens.rCard),
              ),
          ],
        ),
        const SizedBox(height: AppTokens.xl),
        const _FundSkeletonCard(),
        const SizedBox(height: AppTokens.md),
        const _FundSkeletonCard(),
      ],
    );
  }
}

class _FundSkeletonCard extends StatelessWidget {
  const _FundSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Skeleton.line(width: 140),
              Skeleton.box(width: 84, height: 24, radius: AppTokens.rPill),
            ],
          ),
          const SizedBox(height: AppTokens.md),
          Skeleton.box(height: 10, radius: AppTokens.sm),
          const SizedBox(height: AppTokens.sm),
          Skeleton.line(width: 180),
        ],
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: 'Something went wrong',
      message: message,
      showMascot: false,
    );
  }
}
