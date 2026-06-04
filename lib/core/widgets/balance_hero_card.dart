import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

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
  });

  /// Brand/accent color the gradient is derived from.
  final Color seed;

  final String primaryLabel;
  final String primaryAmount;

  final String? secondaryLabel;
  final String? secondaryAmount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // The gradient runs dark, so on-content is white for guaranteed contrast.
    const onGradient = Colors.white;
    final onGradientMuted = Colors.white.withValues(alpha: 0.82);

    final secLabel = secondaryLabel;
    final secAmount = secondaryAmount;
    final hasSecondary = secLabel != null && secAmount != null;

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
          if (hasSecondary) ...[
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
