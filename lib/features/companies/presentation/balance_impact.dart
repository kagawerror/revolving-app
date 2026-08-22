import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';

/// Shared "consequence preview" for any action that moves a fund's available
/// balance. Extracted from the edit-fund dialog so both edit-fund and
/// adjust-fund render the *same* trust surface: the user always sees the
/// money's destination (`current → projected`) before committing.
///
/// API is intentionally tiny:
///   * [currentAvailable] — the live balance now.
///   * [deltaCentavos]    — the signed change the pending action would apply
///     (`+` add, `-` deduct). `null` or `0` => no pending change: render the
///     calm "current balance" line only.
///   * [lowThreshold]     — optional. When the *projected* balance lands at or
///     below it (but stays >= 0), the preview adds a low-balance caution so an
///     approver/admin isn't surprised by a fund dropping into the red band.
///
/// Styling intent:
///   * Increase  => tertiary (positive) tone, trending-up icon.
///   * Decrease  => error (warning) tone, trending-down icon.
///   * The projected figure uses tabular figures so digits never jitter as the
///     user types, and is clamped to >= ₱0 for display (a deduction can never
///     show a negative balance — the caller owns the hard guard).
///
/// Text labels back every color (never color alone), satisfying the app's
/// accessibility rule.
class BalanceImpact extends StatelessWidget {
  const BalanceImpact({
    super.key,
    required this.currentAvailable,
    required this.deltaCentavos,
    this.lowThreshold,
  });

  final Money currentAvailable;
  final int? deltaCentavos;
  final Money? lowThreshold;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final delta = deltaCentavos;
    final hasDelta = delta != null && delta != 0;

    final tabular = <FontFeature>[const FontFeature.tabularFigures()];

    // Calm resting state: no pending change yet.
    if (!hasDelta) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Current available balance ${currentAvailable.format()}',
          style: textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontFeatures: tabular,
          ),
        ),
      );
    }

    final increase = delta > 0;
    // Available balance may never go negative; clamp the projection for display.
    final projectedCentavos =
        (currentAvailable.centavos + delta).clamp(0, 1 << 62);
    final projected = Money.fromCentavos(projectedCentavos);
    final magnitude = Money.fromCentavos(delta.abs());
    final tone = increase ? scheme.tertiary : scheme.error;

    // Caution when the projection lands in (or below) the low band but is still
    // a legal, non-negative balance. Suppressed on increases.
    final threshold = lowThreshold;
    final projectedIsLow = !increase &&
        threshold != null &&
        projected <= threshold;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.md,
        vertical: AppTokens.sm,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: AppTokens.brField,
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                increase
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                size: 18,
                color: tone,
                semanticLabel: increase ? 'Increase' : 'Decrease',
              ),
              const SizedBox(width: AppTokens.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    children: [
                      TextSpan(
                        text: increase
                            ? 'Available balance will increase by '
                            : 'Available balance will decrease by ',
                      ),
                      TextSpan(
                        text: magnitude.format(),
                        style: TextStyle(
                          color: tone,
                          fontWeight: FontWeight.w800,
                          fontFeatures: tabular,
                        ),
                      ),
                      TextSpan(
                        text:
                            ' (${currentAvailable.format()} → ${projected.format()}).',
                        style: TextStyle(fontFeatures: tabular),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (projectedIsLow) ...[
            const SizedBox(height: AppTokens.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: scheme.error,
                  semanticLabel: 'Low balance warning',
                ),
                const SizedBox(width: AppTokens.sm),
                Expanded(
                  child: Text(
                    'This leaves the fund at or below its low-balance alert level.',
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
