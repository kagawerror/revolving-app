import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Semantic tone of a status, mapped to readable color roles.
enum StatusTone { neutral, info, success, warning, danger }

/// Compact, stadium-shaped status chip used app-wide so the same status always
/// looks the same. Never color-only — always carries a text label (and an
/// optional leading icon) for accessibility.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;

  /// Pure, unit-testable mapping from a [StatusTone] to its `(bg, fg)` colors
  /// for the given [scheme]. Kept static so it can be tested without pumping a
  /// widget and reused by callers that need matching color accents.
  static (Color bg, Color fg) colorsFor(StatusTone tone, ColorScheme scheme) {
    switch (tone) {
      case StatusTone.success:
        return (scheme.tertiaryContainer, scheme.onTertiaryContainer);
      case StatusTone.danger:
        return (scheme.errorContainer, scheme.onErrorContainer);
      case StatusTone.warning:
        // No amber role exists in the M3 scheme, so it's hand-tuned — but
        // brightness-aware so a warning pill tones down on dark surfaces
        // instead of glowing as a bright island. Both pairs pass WCAG AA.
        return scheme.brightness == Brightness.dark
            ? (const Color(0xFF4A3413), const Color(0xFFFFD79A))
            : (const Color(0xFFFDE7C3), const Color(0xFF7A4B00));
      case StatusTone.info:
        return (scheme.primaryContainer, scheme.onPrimaryContainer);
      case StatusTone.neutral:
        return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = colorsFor(tone, scheme);
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        );

    return Semantics(
      label: 'Status: $label',
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.md,
          vertical: AppTokens.xs + 2,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppTokens.rPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: AppTokens.xs + 2),
            ],
            Text(label, style: textStyle),
          ],
        ),
      ),
    );
  }
}
