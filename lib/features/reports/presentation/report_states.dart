import 'package:flutter/material.dart';

import '../../../core/error/failure.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';

/// Shared presentation scaffolding for both report tabs: the list-with-footer
/// layout, the error view, and the loading skeleton. Kept in one file so the
/// two bodies render identically and a tweak applies to both.

/// A report list with a pinned grand-total footer bar. The list scrolls; the
/// total stays put at the bottom so it is always visible while the custodian
/// scans rows — the single number that must never be missed.
///
/// Rows are separated by a hairline divider rather than gaps so the result
/// reads as a continuous ledger. Bottom content inset clears nothing here (the
/// footer is outside the scroll view), so the list padding is symmetric.
class ReportListScaffold extends StatelessWidget {
  const ReportListScaffold({
    super.key,
    required this.totalLabel,
    required this.total,
    required this.itemCount,
    required this.itemBuilder,
    this.truncated = false,
    this.cap = 500,
    this.separated = true,
    this.totalItemCount,
  });

  final String totalLabel;
  final Money total;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// True when the query hit its row cap; surfaces a "showing first [cap]" note
  /// above the total so the figure isn't read as complete.
  final bool truncated;
  final int cap;

  /// When true the list draws hairline dividers between items (the continuous
  /// ledger look). When false items are rendered plain — used by the grouped
  /// released view, where headers/subtotals provide their own separation.
  final bool separated;

  /// The count surfaced in the footer's "N items" label. When null, the footer
  /// falls back to [itemCount]; the grouped released view passes the row count
  /// explicitly because it iterates *entries* (headers + rows + subtotals).
  final int? totalItemCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    const listPadding = EdgeInsets.fromLTRB(
      AppTokens.lg,
      AppTokens.sm,
      AppTokens.lg,
      AppTokens.lg,
    );

    return Column(
      children: [
        Expanded(
          child: separated
              ? ListView.separated(
                  padding: listPadding,
                  itemCount: itemCount,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    thickness: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  itemBuilder: itemBuilder,
                )
              : ListView.builder(
                  padding: listPadding,
                  itemCount: itemCount,
                  itemBuilder: itemBuilder,
                ),
        ),
        if (truncated) _TruncatedNote(cap: cap),
        _GrandTotalBar(
          label: totalLabel,
          total: total,
          itemCount: totalItemCount ?? itemCount,
        ),
      ],
    );
  }
}

/// Banner shown above the total when the report only covers a capped slice of
/// the window — so the grand total reads as a lower bound, not the full figure.
class _TruncatedNote extends StatelessWidget {
  const _TruncatedNote({required this.cap});

  final int cap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(
        AppTokens.lg,
        AppTokens.sm,
        AppTokens.lg,
        0,
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppTokens.xs),
          Expanded(
            child: Text(
              'Showing first $cap. Narrow the period for a complete total.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned footer summarizing the visible report: row count on the left, the
/// label + summed amount on the right. Sits on a raised surface tier with a top
/// hairline so it reads as a fixed summary distinct from the scrolling rows.
class _GrandTotalBar extends StatelessWidget {
  const _GrandTotalBar({
    required this.label,
    required this.total,
    required this.itemCount,
  });

  final String label;
  final Money total;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rowsLabel = itemCount == 1 ? '1 item' : '$itemCount items';

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.lg,
            vertical: AppTokens.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                rowsLabel,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                label,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppTokens.md),
              Text(
                total.format(),
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Error view for a report tab. Maps the [Failure] to its user-safe message via
/// the shared [Failure.message] (the same text [FailureSnackBar] would show) and
/// offers a retry. Falls back to a generic line if the error wasn't a [Failure]
/// (defensive — repositories return Failures, but the AsyncValue type is open).
class ReportErrorView extends StatelessWidget {
  const ReportErrorView({super.key, required this.onRetry, this.failure});

  final Failure? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = failure?.message ?? 'Could not load this report.';
    return EmptyState(
      title: 'Something went wrong',
      message: message,
      showMascot: false,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Retry'),
      ),
    );
  }
}

/// Loading state for a report tab: shimmer rows plus a shimmer footer, matching
/// the populated layout so nothing jumps when data arrives — the same care the
/// dashboard takes with its skeletons.
class ReportListSkeleton extends StatelessWidget {
  const ReportListSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.lg,
              AppTokens.sm,
              AppTokens.lg,
              AppTokens.lg,
            ),
            itemCount: rows,
            separatorBuilder: (_, _) => const SizedBox(height: AppTokens.lg),
            itemBuilder: (_, _) => Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton.line(width: 150),
                      const SizedBox(height: AppTokens.sm),
                      Skeleton.line(width: 100),
                    ],
                  ),
                ),
                const SizedBox(width: AppTokens.md),
                Skeleton.box(width: 84, height: 18, radius: 6),
              ],
            ),
          ),
        ),
        Container(
          color: scheme.surfaceContainerHigh,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.lg,
            vertical: AppTokens.lg,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Skeleton.line(width: 70),
              Skeleton.box(width: 120, height: 20, radius: 6),
            ],
          ),
        ),
      ],
    );
  }
}
