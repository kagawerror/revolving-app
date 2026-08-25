import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/money/money.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../replenishment/domain/liquidation_history.dart';
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
    this.entries,
  }) : assert(entries == null || !compact,
            'entries is a full-variant concern; the compact variant must keep '
            'using breakdown.approvedPartial/pendingPartial.');

  final RequestBreakdown breakdown;

  /// `true` → dense trailing-column variant; `false` → roomy detail variant.
  final bool compact;

  /// Itemized liquidation ledger for the FULL variant only. When non-null it
  /// replaces the two lumped middle rows with one row per report line; `null`
  /// (loading, stream error, or an uninterested caller) degrades to those
  /// lumped rows, which are always correct totals.
  final List<LiquidationEntry>? entries;

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
        : _FullBreakdown(breakdown: breakdown, entries: entries);
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
  const _FullBreakdown({required this.breakdown, this.entries});

  final RequestBreakdown breakdown;

  /// See [RequestBreakdownView.entries]. Three states drive the middle band:
  /// `null` → lumped rows, `[]` → muted placeholder, non-empty → one row each.
  final List<LiquidationEntry>? entries;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      label: _semanticSummary(breakdown, entries),
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
          ..._middleBand(),
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

  /// The rows between `Original` and `Remaining`. Three states, no spinner —
  /// the band always shows something arithmetically true.
  List<Widget> _middleBand() {
    final items = entries;

    // Loading / stream error / caller not interested → the lumped totals.
    if (items == null) {
      return [
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
      ];
    }

    // Resolved but empty (e.g. legacy reports carrying no line items): say so
    // rather than leaving a silent gap between the two totals.
    if (items.isEmpty) {
      return const [
        SizedBox(height: AppTokens.sm),
        _EmptyHistoryRow(),
      ];
    }

    return [
      for (final e in items) ...[
        const SizedBox(height: AppTokens.sm),
        _FullRow(
          label: _entryLabel(e),
          amount: e.amount,
          negative: true,
          tone: _entryTone(e.status),
        ),
      ],
    ];
  }
}

/// `Partial · Jan 5, 2026 · approved`. A null date (legacy report) reads as a
/// dash instead of crashing or inventing a timestamp.
String _entryLabel(LiquidationEntry e) {
  final kind = e.isPartial ? 'Partial' : 'Full';
  final when = e.date == null
      ? '—'
      : DateFormat('MMM d, yyyy').format(e.date!.toLocal());
  return '$kind · $when · ${_statusWord(e.status)}';
}

String _statusWord(LiquidationEntryStatus status) => switch (status) {
      LiquidationEntryStatus.approved => 'approved',
      LiquidationEntryStatus.forApproval => 'for approval',
      LiquidationEntryStatus.rejected => 'rejected',
    };

StatusTone _entryTone(LiquidationEntryStatus status) => switch (status) {
      LiquidationEntryStatus.approved => StatusTone.success,
      LiquidationEntryStatus.forApproval => StatusTone.warning,
      LiquidationEntryStatus.rejected => StatusTone.danger,
    };

/// Muted stand-in for "we looked, there is nothing itemized to show". Mirrors
/// [_FullRow]'s label/value geometry so the column stays visually aligned.
class _EmptyHistoryRow extends StatelessWidget {
  const _EmptyHistoryRow();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text('Liquidation history', style: muted)),
            const SizedBox(width: AppTokens.md),
            Text('—', textAlign: TextAlign.end, style: muted),
          ],
        ),
        const SizedBox(height: AppTokens.xs),
        Text(
          'No itemized history available.',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
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
///
/// [entries] must be whatever the widget actually rendered, so the spoken and
/// visual content agree: non-empty → the itemized rows are narrated using the
/// same `Partial · <date> · <status>` labels shown on screen; `[]` → "no
/// itemized history", matching the [_EmptyHistoryRow] placeholder; `null`
/// (still loading, or the stream errored) → the legacy lumped description,
/// which is also what [_middleBand] renders in that state.
String _semanticSummary(RequestBreakdown b, [List<LiquidationEntry>? entries]) {
  final parts = <String>['Original ${b.original.format()}'];

  if (entries == null) {
    if (b.hasApproved) {
      parts.add('approved partial ${b.approvedPartial.format()}');
    }
    if (b.hasPending) {
      parts.add('partial for approval ${b.pendingPartial.format()}');
    }
  } else if (entries.isEmpty) {
    parts.add('no itemized history available');
  } else {
    for (final e in entries) {
      parts.add('${_entryLabel(e)}, minus ${e.amount.format()}');
    }
  }

  final tail = b.hasPending ? ' including pending' : '';
  parts.add('remaining ${b.projectedRemaining.format()}$tail');
  return parts.join(', ');
}
