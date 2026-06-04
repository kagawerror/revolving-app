import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_tokens.dart';

/// A compact metric card (label + value, optional icon) sized to flow nicely in
/// a [Wrap] or grid. Animates in with a gentle fade + slide so dashboards feel
/// alive without being noisy.
///
/// The [value] is pre-formatted by the caller (e.g. via `Money.format()`).
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone,
    this.minWidth = 150,
  });

  final String label;
  final String value;
  final IconData? icon;

  /// Optional accent applied to the icon chip; defaults to the scheme primary.
  final Color? tone;

  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = tone ?? scheme.primary;

    return Container(
      constraints: BoxConstraints(minWidth: minWidth),
      padding: const EdgeInsets.all(AppTokens.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppTokens.brCard,
        boxShadow: AppTokens.softShadow(scheme.shadow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(AppTokens.sm),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: AppTokens.brField,
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
            const SizedBox(height: AppTokens.md),
          ],
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppTokens.xs),
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 280.ms).slideY(begin: 0.08, end: 0);
  }
}
