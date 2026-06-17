import 'package:flutter/material.dart';

import '../../domain/fund_audit_math.dart';

/// Semantic palette for an [AuditVerdict], derived from the active
/// [ColorScheme] so it tracks the user's accent + light/dark mode. Never a raw
/// hex: shortage borrows `error`, overage borrows `tertiary` (the app's amber
/// "replenishing" hue used on the dashboard), balanced borrows `primary`.
class VerdictColors {
  const VerdictColors({
    required this.fg,
    required this.bg,
    required this.onBg,
  });

  /// Strong color for the value / icon.
  final Color fg;

  /// Container fill for the chip / banner.
  final Color bg;

  /// Text color that reads on [bg].
  final Color onBg;

  factory VerdictColors.of(ColorScheme scheme, AuditVerdict verdict) {
    switch (verdict) {
      case AuditVerdict.shortage:
        return VerdictColors(
          fg: scheme.error,
          bg: scheme.errorContainer,
          onBg: scheme.onErrorContainer,
        );
      case AuditVerdict.overage:
        return VerdictColors(
          fg: scheme.tertiary,
          bg: scheme.tertiaryContainer,
          onBg: scheme.onTertiaryContainer,
        );
      case AuditVerdict.balanced:
        return VerdictColors(
          fg: scheme.primary,
          bg: scheme.primaryContainer,
          onBg: scheme.onPrimaryContainer,
        );
    }
  }
}

extension AuditVerdictUi on AuditVerdict {
  String get label => switch (this) {
        AuditVerdict.shortage => 'SHORTAGE',
        AuditVerdict.overage => 'OVERAGE',
        AuditVerdict.balanced => 'BALANCED',
      };

  IconData get icon => switch (this) {
        AuditVerdict.shortage => Icons.trending_down_rounded,
        AuditVerdict.overage => Icons.trending_up_rounded,
        AuditVerdict.balanced => Icons.check_circle_rounded,
      };
}

/// Color-coded, always text-labeled verdict pill (never color alone). Used
/// identically on the create card, history tiles, and detail certificate so a
/// given verdict reads the same everywhere.
class VerdictChip extends StatelessWidget {
  const VerdictChip({
    super.key,
    required this.verdict,
    this.large = false,
  });

  final AuditVerdict verdict;

  /// Hero size for the detail certificate; compact for tiles.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = VerdictColors.of(scheme, verdict);
    final text = verdict.label;

    final labelStyle = (large
            ? Theme.of(context).textTheme.titleMedium
            : Theme.of(context).textTheme.labelLarge)
        ?.copyWith(
      color: c.onBg,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
    );

    return Semantics(
      label: 'Verdict: $text',
      container: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: large ? 16 : 12,
          vertical: large ? 10 : 6,
        ),
        decoration: ShapeDecoration(
          color: c.bg,
          shape: StadiumBorder(side: BorderSide(color: c.fg.withValues(alpha: 0.35))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(verdict.icon, size: large ? 22 : 16, color: c.fg),
            const SizedBox(width: 6),
            Text(text, style: labelStyle),
          ],
        ),
      ),
    );
  }
}
