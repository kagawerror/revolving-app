import 'package:flutter/material.dart';

import '../../../../core/money/money.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../domain/request_breakdown.dart';

/// Renders a [RequestBreakdown] in one of two densities sharing a single
/// implementation:
///
/// * `compact` — for the incharge home request-row trailing column. Right
///   aligned, caption-sized partial lines, tight spacing; collapses to a single
///   amount line when there are no partials (so plain requests look unchanged).
/// * full — for the request detail screen. Left-aligned label/value rows with
///   breathing room, intended to sit inside a [SurfaceCard] section.
///
/// All money uses tabular figures so digits line up vertically. Tones come from
/// the shared [StatusTone] mapping (warning = "for approval", success =
/// "approved") via [StatusPill.colorsFor] — no raw hex, no parallel palette.
class RequestBreakdownView extends StatelessWidget {
  const RequestBreakdownView({
    super.key,
    required this.breakdown,
    this.compact = true,
  });

  final RequestBreakdown breakdown;

  /// `true` → dense trailing-column variant; `false` → roomy detail variant.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // No partials → behave exactly like the legacy single-amount line so plain
    // requests are visually untouched. The caller decides whether to even mount
    // this widget, but collapsing here keeps the contract self-contained.
    if (!breakdown.hasAnyPartial) {
      return _AmountText(
        amount: breakdown.original,
        compact: compact,
      );
    }
    return compact
        ? _CompactBreakdown(breakdown: breakdown)
        : _FullBreakdown(breakdown: breakdown);
  }
}

// ---------------------------------------------------------------------------
// Compact variant — trailing column of an AppListTile row.
// ---------------------------------------------------------------------------

class _CompactBreakdown extends StatelessWidget {
  const _CompactBreakdown({required this.breakdown});

  final RequestBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      label: _semanticSummary(breakdown),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Original amount, matching the existing row's titleMedium/w800.
          _AmountText(amount: breakdown.original, compact: true),
          const SizedBox(height: 2),
          // One subtraction line per present partial state. Pending first so the
          // most "actionable" (not-yet-final) money is closest to the original.
          if (breakdown.hasPending)
            _CompactPartialLine(
              amount: breakdown.pendingPartial,
              hint: 'partial · for approval',
              tone: StatusTone.warning,
            ),
          if (breakdown.hasApproved)
            _CompactPartialLine(
              amount: breakdown.approvedPartial,
              hint: 'partial · approved',
              tone: StatusTone.success,
            ),
          // Thin rule above the remaining line (the "----" in the spec). Sized
          // to the content so it doesn't stretch the trailing column.
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppTokens.xs - 1),
            child: SizedBox(
              width: 96,
              child: Divider(height: 1, thickness: 1),
            ),
          ),
          // Projected remaining — the figure that matters for the row.
          Text(
            breakdown.projectedRemaining.format(),
            textAlign: TextAlign.end,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            breakdown.hasPending ? 'remaining (incl. pending)' : 'remaining',
            textAlign: TextAlign.end,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single dense "- {amount}  {hint}" line. The amount carries the tone's
/// foreground colour so debit lines read as their state at a glance; the hint
/// is muted caption text. Never colour-only — every line is text-labelled.
class _CompactPartialLine extends StatelessWidget {
  const _CompactPartialLine({
    required this.amount,
    required this.hint,
    required this.tone,
  });

  final Money amount;
  final String hint;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final (_, fg) = StatusPill.colorsFor(tone, scheme);

    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            hint,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppTokens.sm),
          Text(
            '- ${amount.format()}',
            style: textTheme.bodySmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full variant — roomy detail section (sits inside a SurfaceCard).
// ---------------------------------------------------------------------------

class _FullBreakdown extends StatelessWidget {
  const _FullBreakdown({required this.breakdown});

  final RequestBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      label: _semanticSummary(breakdown),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Breakdown',
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.sm),
          _FullRow(
            label: 'Original',
            amount: breakdown.original,
            valueStyle: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (breakdown.hasPending) ...[
            const SizedBox(height: AppTokens.sm),
            _FullRow(
              label: 'Partial · for approval',
              amount: breakdown.pendingPartial,
              negative: true,
              tone: StatusTone.warning,
            ),
          ],
          if (breakdown.hasApproved) ...[
            const SizedBox(height: AppTokens.sm),
            _FullRow(
              label: 'Partial · approved',
              amount: breakdown.approvedPartial,
              negative: true,
              tone: StatusTone.success,
            ),
          ],
          const SizedBox(height: AppTokens.md),
          const Divider(height: 1),
          const SizedBox(height: AppTokens.md),
          _FullRow(
            label: breakdown.hasPending
                ? 'Remaining (incl. pending)'
                : 'Remaining',
            amount: breakdown.projectedRemaining,
            valueStyle: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            emphasiseLabel: true,
          ),
          if (breakdown.hasPending) ...[
            const SizedBox(height: AppTokens.xs),
            Text(
              'Pending partials are not yet approved and may still change.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A left-label / right-value row for the full variant. When [negative] the
/// value is prefixed with "−" and tinted by [tone]'s foreground.
class _FullRow extends StatelessWidget {
  const _FullRow({
    required this.label,
    required this.amount,
    this.negative = false,
    this.tone,
    this.valueStyle,
    this.emphasiseLabel = false,
  });

  final String label;
  final Money amount;
  final bool negative;
  final StatusTone? tone;
  final TextStyle? valueStyle;
  final bool emphasiseLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Color? valueColor;
    if (negative && tone != null) {
      final (_, fg) = StatusPill.colorsFor(tone!, scheme);
      valueColor = fg;
    }

    final resolvedValueStyle = (valueStyle ??
            textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ))
        ?.copyWith(color: valueColor);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasiseLabel
                ? textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
                : textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: AppTokens.md),
        Text(
          negative ? '− ${amount.format()}' : amount.format(),
          textAlign: TextAlign.end,
          style: resolvedValueStyle,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits.
// ---------------------------------------------------------------------------

/// The plain original-amount line, matching whichever density it's used in.
/// Compact mirrors the existing row's `titleMedium`/w800; full uses a headline.
class _AmountText extends StatelessWidget {
  const _AmountText({required this.amount, required this.compact});

  final Money amount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final base = compact ? textTheme.titleMedium : textTheme.headlineSmall;
    return Text(
      amount.format(),
      textAlign: compact ? TextAlign.end : TextAlign.start,
      style: base?.copyWith(
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// A11y: a single spoken sentence rather than a fragmentary digit-by-digit read.
String _semanticSummary(RequestBreakdown b) {
  final parts = <String>['Original ${b.original.format()}'];
  if (b.hasApproved) parts.add('approved partial ${b.approvedPartial.format()}');
  if (b.hasPending) {
    parts.add('partial for approval ${b.pendingPartial.format()}');
  }
  final tail = b.hasPending ? ' including pending' : '';
  parts.add('remaining ${b.projectedRemaining.format()}$tail');
  return parts.join(', ');
}
