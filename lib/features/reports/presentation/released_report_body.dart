import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/error/failure.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/report_math.dart';
import 'report_providers.dart';
import 'report_states.dart';

/// Released-requests tab body: a scrollable list of releases for the active
/// period with a pinned grand-total bar. Body-only — [ReportScreen] owns the
/// Scaffold, AppBar, and period header.
///
/// Each row shows beneficiary (primary), purpose (secondary), the release date,
/// and the amount (right-aligned, tabular). Rows still awaiting sync
/// (`datePending`) carry a "Pending sync" chip and fall back to `createdAt` for
/// their date, so an offline-captured release reads honestly rather than
/// showing a blank or wrong date.
class ReleasedReportBody extends ConsumerWidget {
  const ReleasedReportBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(releasedReportProvider);

    return report.when(
      loading: () => const ReportListSkeleton(),
      error: (e, _) => ReportErrorView(
        failure: e is Failure ? e : null,
        onRetry: () => ref.invalidate(releasedReportProvider),
      ),
      data: (summary) {
        final rows = summary.rows;
        if (rows.isEmpty) {
          return const EmptyState(
            title: 'Nothing released',
            message: 'No released requests in this period.',
          );
        }
        final entries = buildReleasedEntries(rows);
        return ReportListScaffold(
          totalLabel: 'Grand total',
          total: summary.grandTotal,
          itemCount: entries.length,
          totalItemCount: rows.length,
          separated: false,
          truncated: summary.truncated,
          itemBuilder: (context, i) {
            final entry = entries[i];
            final child = switch (entry) {
              FundHeaderEntry(:final fundName) => _FundGroupHeader(
                fundName: fundName,
              ),
              ReleasedRowEntry(:final row) => _ReleasedRow(row: row),
              FundSubtotalEntry(:final fundName, :final amount) =>
                _FundSubtotalRow(fundName: fundName, amount: amount),
            };
            return child.animate().fadeIn(duration: 200.ms, delay: (28 * i).ms);
          },
        );
      },
    );
  }
}

/// One renderable line in the grouped released list: a fund header, a released
/// row, or a per-fund subtotal. Built by [buildReleasedEntries] so the list,
/// the animation stagger, and the footer all iterate the same flattened model.
sealed class ReportEntry {}

class FundHeaderEntry extends ReportEntry {
  FundHeaderEntry(this.fundName);

  final String fundName;
}

class ReleasedRowEntry extends ReportEntry {
  ReleasedRowEntry(this.row);

  final ReleasedRequestRow row;
}

class FundSubtotalEntry extends ReportEntry {
  FundSubtotalEntry(this.fundName, this.amount);

  final String fundName;
  final Money amount;
}

/// Flattens released rows into [ReportEntry]s grouped by fund: each group emits
/// a header, its rows (oldest-first), then a subtotal. Pure — exercised by unit
/// tests against [groupByFund].
List<ReportEntry> buildReleasedEntries(List<ReleasedRequestRow> rows) {
  final groups = groupByFund<ReleasedRequestRow>(
    rows,
    (r) => r.fundName,
    (r) => r.amount,
    (r) => r.datePending ? null : r.effectiveDate,
  );
  final entries = <ReportEntry>[];
  for (final g in groups) {
    entries.add(FundHeaderEntry(g.fundName));
    for (final r in g.rows) {
      entries.add(ReleasedRowEntry(r));
    }
    entries.add(FundSubtotalEntry(g.fundName, g.subtotal));
  }
  return entries;
}

/// Fund group header: an accent bar + the fund name in caps. Marked as a
/// semantics header so screen readers announce the grouping boundary.
class _FundGroupHeader extends StatelessWidget {
  const _FundGroupHeader({required this.fundName});

  final String fundName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.md,
          vertical: AppTokens.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppTokens.sm),
            Expanded(
              child: Text(
                fundName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelLarge?.copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-fund subtotal row: a top hairline, then a right-aligned "Subtotal · Fund"
/// label and the summed amount in the accent colour with tabular figures.
class _FundSubtotalRow extends StatelessWidget {
  const _FundSubtotalRow({required this.fundName, required this.amount});

  final String fundName;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: 'Subtotal for $fundName ${amount.format()}',
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.md,
          vertical: AppTokens.sm,
        ),
        child: Row(
          children: [
            const Spacer(),
            Text(
              'Subtotal · $fundName',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppTokens.md),
            Text(
              amount.format(),
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleasedRow extends StatelessWidget {
  const _ReleasedRow({required this.row});

  final ReleasedRequestRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // effectiveDate already resolves to createdAt for pending rows (per the
    // provider contract); we format it the same either way: "Jun 13".
    final dateLabel = DateFormat('MMM d').format(row.effectiveDate);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.md,
        vertical: AppTokens.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Beneficiary + purpose. Takes the flexible space; both lines clamp
          // so a long purpose never pushes the amount off-screen.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  row.beneficiaryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (row.purpose.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      row.purpose,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (row.datePending)
                  const Padding(
                    padding: EdgeInsets.only(top: AppTokens.xs),
                    child: StatusPill(
                      label: 'Pending sync',
                      tone: StatusTone.warning,
                      icon: Icons.cloud_upload_rounded,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.md),
          // Date + amount, right-aligned. Amount is the dominant figure with
          // tabular numerals so the column reads as a clean ledger.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                dateLabel,
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                row.amount.format(),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
