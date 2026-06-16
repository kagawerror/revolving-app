import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// One label/amount line in the hero card's breakdown section. [emphasis] makes
/// the row stand out (used for the final "Total budget").
class HeroRow {
  const HeroRow(this.label, this.amount, {this.emphasis = false});
  final String label;
  final String amount;
  final bool emphasis;
}

/// The bold, gradient "hero" card that headlines a fund balance. The amount is
/// the single most important figure on a screen, so it is rendered large and
/// high-contrast over a seed-derived gradient.
///
/// Amount strings are PRE-FORMATTED by the caller (via `Money.format()`); this
/// widget performs no money logic so it can never mis-format centavos.
class BalanceHeroCard extends StatelessWidget {
  const BalanceHeroCard({
    super.key,
    required this.seed,
    required this.primaryLabel,
    required this.primaryAmount,
    this.secondaryLabel,
    this.secondaryAmount,
    this.rows,
  });

  /// Brand/accent color the gradient is derived from.
  final Color seed;

  final String primaryLabel;
  final String primaryAmount;

  final String? secondaryLabel;
  final String? secondaryAmount;

  /// Optional multi-row breakdown shown beneath the primary amount. When
  /// provided (non-empty), it takes precedence over [secondaryLabel]/[secondaryAmount].
  final List<HeroRow>? rows;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // The gradient runs dark, so on-content is white for guaranteed contrast.
    const onGradient = Colors.white;
    final onGradientMuted = Colors.white.withValues(alpha: 0.82);

    final secLabel = secondaryLabel;
    final secAmount = secondaryAmount;
    final hasSecondary = secLabel != null && secAmount != null;

    final multi = rows;
    final showMulti = multi != null && multi.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.xl),
      decoration: BoxDecoration(
        gradient: AppTokens.heroGradient(seed),
        borderRadius: AppTokens.brCard,
        boxShadow: AppTokens.softShadow(seed),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primaryLabel,
            style: textTheme.labelLarge?.copyWith(
              color: onGradientMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppTokens.xs),
          Text(
            primaryAmount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.displaySmall?.copyWith(
              color: onGradient,
              fontWeight: FontWeight.w800,
              // Tabular figures keep digits aligned and unmistakable.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (showMulti) ...[
            const SizedBox(height: AppTokens.lg),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
            const SizedBox(height: AppTokens.md),
            for (var i = 0; i < multi.length; i++) ...[
              if (i > 0) const SizedBox(height: AppTokens.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    multi[i].label,
                    style: textTheme.bodyMedium?.copyWith(
                      color: multi[i].emphasis ? onGradient : onGradientMuted,
                      fontWeight: multi[i].emphasis ? FontWeight.w700 : null,
                    ),
                  ),
                  Text(
                    multi[i].amount,
                    style: (multi[i].emphasis
                            ? textTheme.titleMedium
                            : textTheme.bodyLarge)
                        ?.copyWith(
                      color: onGradient,
                      fontWeight:
                          multi[i].emphasis ? FontWeight.w800 : FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ] else if (hasSecondary) ...[
            const SizedBox(height: AppTokens.lg),
            Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.18),
            ),
            const SizedBox(height: AppTokens.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  secLabel,
                  style: textTheme.bodyMedium?.copyWith(
                    color: onGradientMuted,
                  ),
                ),
                Text(
                  secAmount,
                  style: textTheme.titleMedium?.copyWith(
                    color: onGradient,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
