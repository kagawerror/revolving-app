import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
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
import '../../requests/domain/request_breakdown.dart';
import '../../requests/presentation/request_status_visual.dart';
import '../../requests/presentation/widgets/request_breakdown_view.dart';
import '../../requests/presentation/widgets/request_detail_sheet.dart';
import '../domain/dashboard_summary.dart';
import 'activity_history_providers.dart';
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
          const SectionHeader(title: 'Activity history'),
          const _ActivityHistorySection(),
        ],
      ),
    );
  }
}

/// Formats a signed centavo amount as currency with an explicit sign, e.g.
/// `+₱975,000.00` / `-₱200,000.00` / `₱0.00`. Avoids passing a negative to
/// `Money.fromCentavos` (which throws). Uses ASCII `-`/`+` to match the sign
/// `NumberFormat` itself emits and for reliable screen-reader announcement.
String _signedMoney(int centavos) {
  if (centavos == 0) return Money.zero.format();
  final sign = centavos > 0 ? '+' : '-';
  return '$sign${Money.fromCentavos(centavos.abs()).format()}';
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
      rows: [
        HeroRow('Original budget', t.totalBudget.format()),
        HeroRow('Adjustment', _signedMoney(t.totalAdjustmentsCentavos)),
        HeroRow('Total budget', t.effectiveBudget.format(), emphasis: true),
      ],
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

class _RecentSection extends ConsumerWidget {
  const _RecentSection({required this.recent});

  final AsyncValue<List<FundRequest>> recent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the role-scoped pending-partial map once here and pass each row its
    // own amount, rather than letting every tile watch the provider (which would
    // cause a rebuild storm on every replenishment stream tick).
    final pendingPartials = ref.watch(dashboardPendingPartialByRequestProvider);

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
                _RecentTile(
                  request: list[i],
                  pendingPartial:
                      pendingPartials[list[i].id] ?? Money.fromCentavos(0),
                ).animate().fadeIn(duration: 220.ms, delay: (40 * i).ms),
            ],
          ),
        );
      },
    );
  }
}

/// Builds the second subtitle line for a recent-activity tile, showing the
/// request's created date and — once released — its released date.
///
/// `createdAt`/`releasedAt` are server timestamps and may be null:
///   - `createdAt` is null only briefly while an offline create awaits its
///     server timestamp (optimistic local doc).
///   - `releasedAt` is null for any request that hasn't been released yet
///     (pending / acknowledged / rejected / disputed).
///
/// Return `null` to render no date line at all (the tile falls back to just
/// the purpose).
///
/// Shows the created date alone until a release commits, then appends the
/// released date. Returns null (no line) while a created timestamp is missing.
@visibleForTesting
String? recentDateLine(FundRequest request) {
  final created = request.createdAt;
  if (created == null) return null;
  final released = request.releasedAt;
  if (released == null) return 'Created ${_fmtDate(created)}';
  return 'Created ${_fmtDate(created)} · Released ${_fmtDate(released)}';
}

/// Formats a [DateTime] as `d MMM y` in local time — the app-wide convention.
String _fmtDate(DateTime date) => DateFormat('d MMM y').format(date.toLocal());

// --- Activity history -------------------------------------------------------

/// Browsable month-by-month archive of the company's requests, paged 50 rows at
/// a time. Sits under the (live, capped) "Recent activity" list and answers the
/// "what happened back in March?" question the recent list can't.
class _ActivityHistorySection extends ConsumerWidget {
  const _ActivityHistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activityHistoryControllerProvider);
    // Watched once here, then handed to each row — see [_RecentSection] for why
    // per-tile watching would cause a rebuild storm.
    final pendingPartials = ref.watch(dashboardPendingPartialByRequestProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ActivityHistoryFilterBar(),
        const SizedBox(height: AppTokens.md),
        _ActivityHistoryBody(state: state, pendingPartials: pendingPartials),
        // Only worth any pixels once the archive actually spans >1 page.
        if (state.isPaginated) _ActivityHistoryPager(state: state),
      ],
    );
  }
}

/// Full month name for the Month dropdown, e.g. `March`. The day/year in the
/// probe date are irrelevant — only the month is formatted.
String _monthName(int month) =>
    DateFormat.MMMM().format(DateTime(2000, month, 1));

class _ActivityHistoryFilterBar extends ConsumerWidget {
  const _ActivityHistoryFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(activityHistoryFilterProvider);
    final years = ref.watch(activityHistoryYearsProvider);
    // Stops at the current month in the current year — a future window has no
    // data and would only ever render "No activity in this period".
    final months = ref.watch(activityHistoryMonthsProvider);
    final notifier = ref.read(activityHistoryFilterProvider.notifier);

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.md,
        vertical: AppTokens.sm,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _FilterDropdown<int>(
              dropdownKey: const Key('activityHistoryMonth'),
              label: 'Month',
              icon: Icons.calendar_month_rounded,
              value: filter.month,
              items: {for (final m in months) m: _monthName(m)},
              onChanged: notifier.setMonth,
            ),
          ),
          const SizedBox(width: AppTokens.md),
          Expanded(
            flex: 2,
            child: _FilterDropdown<int>(
              dropdownKey: const Key('activityHistoryYear'),
              label: 'Year',
              icon: Icons.event_rounded,
              value: filter.year,
              items: {for (final y in years) y: '$y'},
              onChanged: notifier.setYear,
            ),
          ),
        ],
      ),
    );
  }
}

/// A labeled, themed dropdown.
///
/// Built on [DropdownButton] (not [DropdownButtonFormField]) on purpose: the
/// form-field variant seeds itself from `initialValue` and never re-syncs when
/// that value changes, so it would drift out of step with the provider the
/// moment the filter is set from anywhere but the dropdown itself.
class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.dropdownKey,
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final Key dropdownKey;
  final String label;
  final IconData icon;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          key: dropdownKey,
          value: value,
          isExpanded: true,
          isDense: true,
          borderRadius: AppTokens.brField,
          items: [
            for (final entry in items.entries)
              DropdownMenuItem<T>(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _ActivityHistoryBody extends StatelessWidget {
  const _ActivityHistoryBody({
    required this.state,
    required this.pendingPartials,
  });

  final ActivityHistoryState state;
  final Map<String, Money> pendingPartials;

  @override
  Widget build(BuildContext context) {
    if (state.loading) {
      return const SurfaceCard(child: SkeletonList(count: 5));
    }
    if (state.failure != null) {
      return const SurfaceCard(
        child: Text('Could not load activity history'),
      );
    }
    if (state.items.isEmpty) {
      return const SurfaceCard(
        child: EmptyState(
          title: 'No activity in this period',
          message: 'Pick another month to look further back.',
        ),
      );
    }
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.xs),
      child: Column(
        children: [
          // No staggered entrance here (unlike the 15-row recent list): a full
          // page is 50 rows, and a per-row delay would run for seconds and
          // animate rows the user has already scrolled past.
          for (final request in state.items)
            _RecentTile(
              request: request,
              pendingPartial: pendingPartials[request.id] ?? Money.zero,
            ),
        ],
      ),
    );
  }
}

class _ActivityHistoryPager extends ConsumerWidget {
  const _ActivityHistoryPager({required this.state});

  final ActivityHistoryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(activityHistoryControllerProvider.notifier);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: state.canGoPrevious ? controller.previousPage : null,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Previous'),
          ),
          Text(
            'Page ${state.pageNumber}',
            style: textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          TextButton.icon(
            onPressed: state.canGoNext ? controller.nextPage : null,
            // Trailing chevron: icon after the label.
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.request, required this.pendingPartial});

  final FundRequest request;
  final Money pendingPartial;

  @override
  Widget build(BuildContext context) {
    final visual = requestStatusVisual(request.status);
    // Compute once and reuse for both the trailing glance view and the
    // read-only detail sheet, threading the pending-partial the tile already
    // holds — never recomputed or refetched.
    final breakdown =
        computeRequestBreakdown(request, pendingPartial: pendingPartial);

    final dateLine = recentDateLine(request);

    return AppListTile(
      title: request.beneficiaryName,
      subtitle: dateLine == null
          ? request.purpose
          : '${request.purpose}\n$dateLine',
      // Two lines so the date line survives instead of being clipped away with
      // everything after the '\n'.
      subtitleMaxLines: 2,
      onTap: () => showRequestDetailSheet(
        context,
        request: request,
        breakdown: breakdown,
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          RequestBreakdownView(
            breakdown: breakdown,
            compact: true,
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
