import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/aging.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'request_detail_screen.dart';
import 'request_status_visual.dart';

/// A single aging row for an outstanding request: beneficiary, tabular amount,
/// truncated purpose, a [RequestStatusBadge] (where the cash stands —
/// released / acknowledged / disputed) and an [AgingChip] showing how long the
/// cash has been outstanding. Tapping opens the shared [RequestDetailScreen].
///
/// Shared by both the incharge [AgingBody] (flat list) and the
/// [AdminAgingBody] (grouped by company), so the row always reads the same.
///
/// The aging report lists ALL cash that is out and not yet replenished, so a
/// row can be [RequestStatus.released], [RequestStatus.acknowledged] or
/// [RequestStatus.disputed]. The status badge below the amount tells those
/// three apart at a glance without competing with the days chip.
class AgingRow extends StatelessWidget {
  const AgingRow({super.key, required this.request, required this.today});

  final FundRequest request;

  /// Captured once by the list body (a single `DateTime.now()`) so every row in
  /// the same render counts against the same "today" — no per-row drift.
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final createdAt = request.createdAt;
    // Null createdAt (server timestamp not yet materialized) counts as 0 days
    // rather than crashing — agingDays clamps to non-negative anyway.
    final days = createdAt == null ? 0 : agingDays(createdAt, today);
    final hasDate = createdAt != null;

    return AppListTile(
      title: request.beneficiaryName,
      subtitle: request.purpose,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            request.amount.format(),
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppTokens.xs),
          RequestStatusBadge(status: request.status),
          const SizedBox(height: AppTokens.xs),
          AgingChip(days: days, hasDate: hasDate),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RequestDetailScreen(request: request),
        ),
      ),
    );
  }
}

/// The summary row that closes out a day-bracket section: a quiet "Total"
/// label on the left and the bracket's summed peso [total] with an "N items"
/// rider on the right. Always the LAST child inside a bracket's card, so it
/// draws its OWN heavier top divider plus a faint surface wash rounded only on
/// the bottom corners — no caller-supplied divider above it.
///
/// Contract: must be the last child of a [SurfaceCard] whose padding leaves the
/// bottom/horizontal edges flush; it rounds its bottom corners to match the
/// card. The wash radius is derived from the SAME [AppTokens.rCard] that
/// [SurfaceCard] uses (via [AppTokens.brCard]) so the corners can't drift.
///
/// Accessibility: the visible label/amount/items are merged into a single
/// `Semantics(label: 'Total: …, … items')` node (the inner content is wrapped
/// in [ExcludeSemantics]) so screen readers announce the summary once, cleanly.
class BracketTotalRow extends StatelessWidget {
  const BracketTotalRow({super.key, required this.total, required this.count});

  final Money total;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final amount = total.format();
    final itemsLabel = count == 1 ? '1 item' : '$count items';

    return Semantics(
      label: 'Total: $amount, $itemsLabel',
      container: true,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(
              height: 1,
              thickness: 1,
              indent: AppTokens.md,
              endIndent: AppTokens.md,
              color: scheme.outlineVariant,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                // Same radius the host SurfaceCard rounds its corners with
                // (AppTokens.rCard / brCard) so the wash sits flush in the
                // card's bottom corners and the two can't drift apart.
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(AppTokens.rCard),
                  bottomRight: Radius.circular(AppTokens.rCard),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.md,
                  AppTokens.sm + AppTokens.xs,
                  AppTokens.md,
                  AppTokens.sm + AppTokens.xs,
                ),
                child: Row(
                  children: [
                    Text(
                      'Total',
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Spacer(),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: amount,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          TextSpan(
                            text: '  ·  $itemsLabel',
                            style: textTheme.labelLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stadium chip showing the outstanding-days count for a released request,
/// colored by aging bucket (green 0–30, amber 31–60, red 61+). Built on the
/// app-wide [StatusPill] so it shares the same shape, padding, and typography
/// as every other status chip — buckets just map onto the existing semantic
/// tones (success / warning / danger), which are already brightness-aware and
/// WCAG-AA in both light and dark themes.
///
/// Accessibility: the "N days" text is the primary signal, so the chip never
/// relies on color alone; the embedded [Icons.schedule_rounded] reinforces
/// "time" without carrying meaning by itself.
class AgingChip extends StatelessWidget {
  const AgingChip({super.key, required this.days, this.hasDate = true});

  final int days;

  /// When false, createdAt was unknown — we show an em dash instead of a
  /// misleading "0 days" and fall back to a neutral tone.
  final bool hasDate;

  /// Pure mapping from an [AgingBucket] to the shared [StatusTone] palette, so
  /// the green/amber/red buckets reuse the app's semantic colors rather than
  /// introducing parallel hardcoded ones.
  static StatusTone toneFor(AgingBucket bucket) {
    switch (bucket) {
      case AgingBucket.green:
        return StatusTone.success;
      case AgingBucket.amber:
        return StatusTone.warning;
      case AgingBucket.red:
        return StatusTone.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!hasDate) {
      return const StatusPill(
        label: '— days',
        tone: StatusTone.neutral,
        icon: Icons.schedule_rounded,
      );
    }
    final tone = toneFor(bucketFor(days));
    final label = days == 1 ? '1 day' : '$days days';
    return StatusPill(
      label: label,
      tone: tone,
      icon: Icons.schedule_rounded,
    );
  }
}

/// Stadium chip showing WHERE the outstanding cash stands in the post-release
/// review flow — released (handed out, not yet reviewed), acknowledged (an
/// approver confirmed it), or disputed (an approver flagged it). Built on the
/// app-wide [StatusPill] so it shares shape, padding and typography with every
/// other status chip, and pulls its tone/label/icon from the single
/// source of truth in [requestStatusVisual] so the same status reads the same
/// here as on the dashboard and the request detail screen.
///
/// Aging rows only ever carry [RequestStatus.released],
/// [RequestStatus.acknowledged] or [RequestStatus.disputed] (the
/// `isReplenishable` set — cash that is out and not yet replenished). The
/// mapping switches exhaustively over the enum and asserts on anything else
/// rather than silently rendering a stray status in a `default` branch.
///
/// Accessibility: never color-only — the chip always carries a text label
/// ("Released" / "Acknowledged" / "Disputed") plus a reinforcing icon, and the
/// underlying [StatusPill] wraps both in a `Semantics(label: 'Status: …')`. The
/// success / info / danger tones are brightness-aware and WCAG-AA in both
/// themes.
class RequestStatusBadge extends StatelessWidget {
  const RequestStatusBadge({super.key, required this.status});

  final RequestStatus status;

  /// Pure, unit-testable mapping for the three outstanding-cash statuses an
  /// aging row can show, in the spirit of [AgingChip.toneFor]. It delegates to
  /// the app-wide [requestStatusVisual] so there is no parallel palette or
  /// wording — it only narrows the exhaustive enum switch to the statuses this
  /// row is contracted to receive, asserting loudly on any other value.
  ///
  /// Tones (from [requestStatusVisual]) read as escalating concern:
  ///   * released     → success — cash correctly handed out, nothing wrong yet
  ///   * acknowledged → info    — reviewed and confirmed, settled/neutral
  ///   * disputed     → danger  — flagged, needs attention
  static ({String label, StatusTone tone, IconData icon}) visualFor(
    RequestStatus status,
  ) {
    switch (status) {
      case RequestStatus.released:
      case RequestStatus.acknowledged:
      case RequestStatus.disputed:
        return requestStatusVisual(status);
      case RequestStatus.created:
      case RequestStatus.conflict:
      case RequestStatus.rejected:
      case RequestStatus.replenished:
        assert(
          false,
          'RequestStatusBadge received non-outstanding status '
          '"${status.name}"; aging rows only show released / acknowledged / '
          'disputed.',
        );
        // Defensive fallback for release builds (asserts are stripped): show
        // the canonical visual rather than crashing a custodian's list.
        return requestStatusVisual(status);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visual = visualFor(status);
    return StatusPill(
      label: visual.label,
      tone: visual.tone,
      icon: visual.icon,
    );
  }
}
