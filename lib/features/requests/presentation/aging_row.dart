import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/aging.dart';
import '../domain/fund_request.dart';
import 'request_detail_screen.dart';

/// A single aging row for a released request: beneficiary, tabular amount,
/// truncated purpose, and an [AgingChip] showing how long the cash has been
/// outstanding. Tapping opens the shared [RequestDetailScreen].
///
/// Shared by both the incharge [AgingBody] (flat list) and the
/// [AdminAgingBody] (grouped by company), so the row always reads the same.
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
