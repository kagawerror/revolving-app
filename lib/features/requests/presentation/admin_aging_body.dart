import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/surface_card.dart';
import '../domain/aging.dart';
import 'aging_body.dart' show AgingErrorView;
import 'aging_providers.dart';
import 'aging_row.dart';

/// Body of the admin Aging view: every company's released requests, grouped
/// under a company-name section header and sorted by company name. Within each
/// section, rows show the running days-outstanding count via an [AgingChip].
///
/// Body-only — the surrounding shell owns the Scaffold and AppBar. Same three
/// async surfaces as the incharge [AgingBody] (shimmer skeleton / friendly
/// empty / error-with-retry).
class AdminAgingBody extends ConsumerWidget {
  const AdminAgingBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncGroups = ref.watch(agingGroupedProvider);

    return asyncGroups.when(
      loading: () => const _AdminAgingLoading(),
      error: (e, _) => AgingErrorView(
        onRetry: () => ref.invalidate(agingGroupedProvider),
      ),
      data: (groups) {
        // A group can technically arrive empty; only show real outstanding work.
        final nonEmpty =
            groups.where((g) => g.requests.isNotEmpty).toList(growable: false);
        return nonEmpty.isEmpty
            ? const _AdminAgingEmpty()
            : _AdminAgingList(groups: nonEmpty);
      },
    );
  }
}

/// Shimmer placeholder mirroring a couple of grouped sections so layout never
/// jumps from a bare spinner to content.
class _AdminAgingLoading extends StatelessWidget {
  const _AdminAgingLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.lg,
        AppTokens.md,
        AppTokens.lg,
        AppTokens.bottomNavContentInset,
      ),
      children: [
        Skeleton.line(width: 140),
        const SizedBox(height: AppTokens.sm),
        const SurfaceCard(child: SkeletonList(count: 3)),
        const SizedBox(height: AppTokens.xl),
        Skeleton.line(width: 110),
        const SizedBox(height: AppTokens.sm),
        const SurfaceCard(child: SkeletonList(count: 2)),
      ],
    );
  }
}

/// Friendly empty state — no released requests across any company.
class _AdminAgingEmpty extends StatelessWidget {
  const _AdminAgingEmpty();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      title: 'Nothing outstanding',
      message: 'No released requests across any company yet. As incharges '
          'release cash, aging rows will appear here grouped by company.',
    );
  }
}

/// The scrolling list of per-company sections: a [SectionHeader] with the
/// company name and an outstanding count, then that company's aging rows in
/// one card.
class _AdminAgingList extends StatelessWidget {
  const _AdminAgingList({required this.groups});

  final List<AgingGroup> groups;

  @override
  Widget build(BuildContext context) {
    // One "now" for the whole render so every row across every company counts
    // against the same day.
    final today = DateTime.now();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.lg,
        AppTokens.xs,
        AppTokens.lg,
        AppTokens.bottomNavContentInset,
      ),
      children: [
        for (final group in groups)
          _AgingSection(
            key: ValueKey(group.company.id),
            group: group,
            today: today,
          ),
      ],
    ).animate().fadeIn(duration: 280.ms).moveY(begin: 8, end: 0, duration: 280.ms);
  }
}

/// One company's section: a name header carrying the outstanding count, then
/// its rows grouped into a single card.
class _AgingSection extends StatelessWidget {
  const _AgingSection({super.key, required this.group, required this.today});

  final AgingGroup group;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final count = group.requests.length;

    // Day-bracket sub-grouping within this company, most-stale-first.
    final brackets = groupByDayBracket(group.requests, today);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Company header stays the dominant header; trailing is item-count only
        // (no peso subtotal at company level — a deliberate scope decision).
        SectionHeader(
          title: group.company.name,
          trailing: Text(
            count == 1 ? '1 item' : '$count items',
            style: textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (var b = 0; b < brackets.length; b++) ...[
          // Subordinate bracket sub-header: a small primary tick + label, with
          // the bracket's item count trailing.
          Padding(
            padding: EdgeInsets.only(
              left: AppTokens.md,
              top: b == 0 ? AppTokens.sm : AppTokens.md,
              bottom: AppTokens.xs,
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(AppTokens.rPill),
                  ),
                ),
                const SizedBox(width: AppTokens.sm),
                Text(
                  bracketLabel(brackets[b].bracket),
                  style: textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  brackets[b].count == 1
                      ? '1 item'
                      : '${brackets[b].count} items',
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SurfaceCard(
            padding: const EdgeInsets.only(top: AppTokens.xs),
            child: Column(
              children: [
                for (var i = 0; i < brackets[b].requests.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      indent: AppTokens.md,
                      endIndent: AppTokens.md,
                    ),
                  AgingRow(
                    key: ValueKey(brackets[b].requests[i].id),
                    request: brackets[b].requests[i],
                    today: today,
                  ),
                ],
                BracketTotalRow(
                  total: brackets[b].total,
                  count: brackets[b].count,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
