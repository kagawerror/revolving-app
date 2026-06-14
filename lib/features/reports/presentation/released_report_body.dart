import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/status_pill.dart';
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
        return ReportListScaffold(
          totalLabel: 'Grand total',
          total: summary.grandTotal,
          itemCount: rows.length,
          truncated: summary.truncated,
          itemBuilder: (context, i) => _ReleasedRow(
            row: rows[i],
          ).animate().fadeIn(duration: 200.ms, delay: (28 * i).ms),
        );
      },
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
