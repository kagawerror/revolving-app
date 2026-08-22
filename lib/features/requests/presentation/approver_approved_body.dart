import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../replenishment/domain/replenishment.dart';
import '../../replenishment/presentation/replenishment_detail_screen.dart';
import '../../replenishment/presentation/replenishment_providers.dart';
import '../../replenishment/presentation/replenishment_status_ui.dart';
import '../domain/fund_request.dart';
import 'approver_inbox_providers.dart';
import 'request_detail_screen.dart';
import 'request_status_visual.dart';

/// Body of the approver "Approved" tab: a read-only revisit list of everything
/// this approver has already acted on, newest-first. Two grouped sections —
/// approved replenishment reports and acted requests (acknowledged / ready /
/// released). These rows have NO inline actions: signing off already happened,
/// and cash release belongs to the incharge worklist, not here.
///
/// Body-only — the [RoleShellScreen] owns the Scaffold, AppBar, and
/// [CompanyContextBar]. Mirrors the pending inbox's grouping
/// ([ApproverHomeBody]) and the worklist body's three async surfaces
/// (shimmer skeleton / friendly empty / error-with-retry), minus any verbs.
class ApproverApprovedBody extends ConsumerWidget {
  const ApproverApprovedBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replenishments = ref.watch(recentApprovedReplenishmentsProvider);
    final requests = ref.watch(recentApprovedRequestsProvider);

    // Both still loading on first paint → one skeleton stand-in so the layout
    // settles in place instead of flashing two separate spinners.
    if (replenishments.isLoading && requests.isLoading) {
      return const _ApprovedLoading();
    }

    // Either side errored → a single retry surface that re-runs BOTH streams,
    // matching the app's invalidate-to-retry idiom.
    if (replenishments.hasError || requests.hasError) {
      return _ApprovedError(
        onRetry: () {
          ref.invalidate(recentApprovedReplenishmentsProvider);
          ref.invalidate(recentApprovedRequestsProvider);
        },
      );
    }

    final replenishmentList = replenishments.valueOrNull ?? const <Replenishment>[];
    final requestList = requests.valueOrNull ?? const <FundRequest>[];

    // Both empty → one friendly, full-bleed empty state rather than two stacked
    // empty cards. Reassures the approver their history is simply clear.
    if (replenishmentList.isEmpty && requestList.isEmpty) {
      return const _ApprovedEmpty();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.lg,
        AppTokens.sm,
        AppTokens.lg,
        AppTokens.bottomNavContentInset,
      ),
      children: [
        SectionHeader(
          title: 'Approved replenishments',
          trailing: replenishmentList.isEmpty
              ? null
              : _CountBadge(count: replenishmentList.length),
        ),
        _ReplenishmentSection(replenishments: replenishmentList),
        SectionHeader(
          title: 'Acted requests',
          trailing: requestList.isEmpty
              ? null
              : _CountBadge(count: requestList.length),
        ),
        _RequestSection(requests: requestList),
      ],
    ).animate().fadeIn(duration: 280.ms).moveY(begin: 8, end: 0, duration: 280.ms);
  }
}

/// Approved replenishment reports, one card. When empty (but the other section
/// has data) shows a quiet inline hint instead of the big mascot empty state.
class _ReplenishmentSection extends StatelessWidget {
  const _ReplenishmentSection({required this.replenishments});

  final List<Replenishment> replenishments;

  @override
  Widget build(BuildContext context) {
    if (replenishments.isEmpty) {
      return const _EmptyHintCard(
        message: 'No replenishment reports approved yet.',
      );
    }
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
      child: Column(
        children: [
          for (var i = 0; i < replenishments.length; i++) ...[
            if (i > 0)
              const Divider(
                  height: 1, indent: AppTokens.md, endIndent: AppTokens.md),
            _ReplenishmentRow(
              key: ValueKey(replenishments[i].id),
              replenishment: replenishments[i],
            ),
          ],
        ],
      ),
    );
  }
}

/// Acted requests (acknowledged / ready / released), one card. Same quiet
/// inline hint when empty alongside a populated replenishment section.
class _RequestSection extends StatelessWidget {
  const _RequestSection({required this.requests});

  final List<FundRequest> requests;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const _EmptyHintCard(
        message: 'No requests acted on yet.',
      );
    }
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
      child: Column(
        children: [
          for (var i = 0; i < requests.length; i++) ...[
            if (i > 0)
              const Divider(
                  height: 1, indent: AppTokens.md, endIndent: AppTokens.md),
            _RequestRow(
              key: ValueKey(requests[i].id),
              request: requests[i],
            ),
          ],
        ],
      ),
    );
  }
}

/// One approved replenishment: fund hint, item count + date subtitle, tabular
/// total, a success-tone status pill, tap into the read-only detail screen.
class _ReplenishmentRow extends StatelessWidget {
  const _ReplenishmentRow({super.key, required this.replenishment});

  final Replenishment replenishment;

  @override
  Widget build(BuildContext context) {
    final r = replenishment;
    final count = r.itemCount;
    final subtitleParts = <String>[
      '$count ${count == 1 ? 'request' : 'requests'}',
      if (r.createdAt != null) _formatDate(r.createdAt!),
    ];

    return AppListTile(
      leading: const _LeadingIcon(
        icon: Icons.autorenew_rounded,
        tone: StatusTone.success,
      ),
      title: 'Replenishment',
      subtitle: subtitleParts.join('  •  '),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _AmountTrailing(text: r.total.format()),
          const SizedBox(height: AppTokens.xs),
          StatusPill(
            label: replenishmentStatusLabel(r.status),
            tone: replenishmentStatusTone(r.status),
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReplenishmentDetailScreen(replenishment: r),
        ),
      ),
    );
  }
}

/// One acted request: beneficiary, truncated purpose, tabular amount, a status
/// pill whose tone/label comes from the shared mapping, tap into the detail
/// screen. No release/reject button — this tab is revisit-only.
class _RequestRow extends StatelessWidget {
  const _RequestRow({super.key, required this.request});

  final FundRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final visual = requestStatusVisual(r.status);

    return AppListTile(
      leading: _LeadingIcon(icon: visual.icon, tone: visual.tone),
      title: r.beneficiaryName,
      subtitle: r.purpose,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _AmountTrailing(text: r.amount.format()),
          const SizedBox(height: AppTokens.xs),
          StatusPill(label: visual.label, tone: visual.tone),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RequestDetailScreen(request: r),
        ),
      ),
    );
  }
}

/// Tabular, right-weighted amount — identical treatment to the pending inbox so
/// the same peso value reads the same everywhere.
class _AmountTrailing extends StatelessWidget {
  const _AmountTrailing({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
    );
  }
}

/// Tinted, rounded leading glyph — same anatomy as the inbox rows.
class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.icon, required this.tone});
  final IconData icon;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = StatusPill.colorsFor(tone, scheme);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: bg, borderRadius: AppTokens.brField),
      child: Icon(icon, color: fg, size: 22),
    );
  }
}

/// Count chip reused from the inbox header treatment.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppTokens.sm + 2, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppTokens.rPill),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

/// Quiet inline placeholder for a section that's empty while the other section
/// has data — keeps the populated section the focus and avoids two big mascots.
class _EmptyHintCard extends StatelessWidget {
  const _EmptyHintCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SurfaceCard(
      child: Row(
        children: [
          Icon(Icons.inbox_rounded, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppTokens.md),
          Expanded(
            child: Text(
              message,
              style:
                  textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Both sections loading → one skeleton card per section, mirroring the final
/// two-section layout so nothing jumps when data arrives.
class _ApprovedLoading extends StatelessWidget {
  const _ApprovedLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.lg,
        AppTokens.sm,
        AppTokens.lg,
        AppTokens.bottomNavContentInset,
      ),
      children: const [
        SectionHeader(title: 'Approved replenishments'),
        SurfaceCard(child: SkeletonList(count: 2)),
        SectionHeader(title: 'Acted requests'),
        SurfaceCard(child: SkeletonList(count: 3)),
      ],
    );
  }
}

/// Both sections empty → a single reassuring empty state.
class _ApprovedEmpty extends StatelessWidget {
  const _ApprovedEmpty();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      title: 'Nothing acted on yet',
      message: 'Once you acknowledge a request or approve a replenishment '
          'report, it moves here so you can revisit it anytime.',
    );
  }
}

/// Error surface with a retry affordance that re-runs both providers — matches
/// the worklist body's error treatment exactly.
class _ApprovedError extends StatelessWidget {
  const _ApprovedError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
            const SizedBox(height: AppTokens.lg),
            Text(
              'Couldn’t load your approved items',
              textAlign: TextAlign.center,
              style:
                  textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppTokens.sm),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppTokens.xl),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Short, locale-aware date hint (e.g. "5 Jun 2026"). Time-of-day is noise on a
/// revisit list, so it's dropped.
String _formatDate(DateTime date) =>
    DateFormat('d MMM y').format(date.toLocal());
