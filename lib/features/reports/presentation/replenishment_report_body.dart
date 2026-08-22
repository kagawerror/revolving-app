import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import 'report_providers.dart';
import 'report_states.dart';

/// Replenishments tab body: signed-off replenishment reports for the active
/// period, each row showing the approved date, the count of bundled requests,
/// and the report total. A pinned grand-total bar sums the period.
///
/// Body-only — [ReportScreen] owns the Scaffold, AppBar, and period header.
class ReplenishmentReportBody extends ConsumerWidget {
  const ReplenishmentReportBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(replenishmentReportProvider);

    return report.when(
      loading: () => const ReportListSkeleton(),
      error: (e, _) => ReportErrorView(
        failure: e is Failure ? e : null,
        onRetry: () => ref.invalidate(replenishmentReportProvider),
      ),
      data: (summary) {
        final rows = summary.rows;
        if (rows.isEmpty) {
          return const EmptyState(
            title: 'Nothing replenished',
            message: 'No replenishments approved in this period.',
          );
        }
        return ReportListScaffold(
          totalLabel: 'Grand total',
          total: summary.grandTotal,
          itemCount: rows.length,
          truncated: summary.truncated,
          itemBuilder: (context, i) => _ReplenishmentRow(
            row: rows[i],
          ).animate().fadeIn(duration: 200.ms, delay: (28 * i).ms),
        );
      },
    );
  }
}

class _ReplenishmentRow extends StatelessWidget {
  const _ReplenishmentRow({required this.row});

  final ReplenishmentRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Prefer the approved date (the event the report is about); fall back to
    // the created date for a not-yet-approved record, and to an em dash if
    // neither is materialized yet (server timestamp pending).
    final date = row.approvedDate ?? row.createdDate;
    final dateLabel = date == null
        ? '—'
        : DateFormat('MMM d, yyyy').format(date);
    final approved = row.approvedDate != null;
    final countLabel = row.itemCount == 1
        ? '1 request'
        : '${row.itemCount} requests';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.md,
        vertical: AppTokens.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Leading badge reinforces "replenishment" without carrying meaning
          // alone — the date + count text are the primary signal.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: AppTokens.brField,
            ),
            child: Icon(
              Icons.replay_circle_filled_rounded,
              size: 20,
              color: scheme.onPrimaryContainer,
              semanticLabel: 'Replenishment',
            ),
          ),
          const SizedBox(width: AppTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  approved ? 'Approved $dateLabel' : dateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    countLabel,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.md),
          Text(
            row.total.format(),
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
