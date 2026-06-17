import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/money/money.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../domain/denomination.dart';

/// Editable cash-count grid: 13 rows, ₱1000 → ₱0.01 (descending).
///
/// Each row pairs a denomination label with a − / number / + stepper and a
/// live right-aligned subtotal. Rows that OCR pre-filled get an accent tint and
/// an "OCR" chip so the custodian knows exactly which counts to double-check;
/// zero rows stay visible but muted (an auditor wants to see the zeros).
class DenominationGrid extends StatelessWidget {
  const DenominationGrid({
    super.key,
    required this.counts,
    required this.ocrPrefilled,
    required this.onSetCount,
    required this.onIncrement,
    required this.onDecrement,
    this.enabled = true,
  });

  final Map<Denomination, int> counts;
  final Set<Denomination> ocrPrefilled;
  final void Function(Denomination, int) onSetCount;
  final void Function(Denomination) onIncrement;
  final void Function(Denomination) onDecrement;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _GridHeader(),
        for (var i = 0; i < kDenominationsDescending.length; i++)
          _DenominationRow(
            key: ValueKey(kDenominationsDescending[i]),
            denomination: kDenominationsDescending[i],
            count: counts[kDenominationsDescending[i]] ?? 0,
            ocr: ocrPrefilled.contains(kDenominationsDescending[i]),
            isLast: i == kDenominationsDescending.length - 1,
            enabled: enabled,
            onSetCount: onSetCount,
            onIncrement: onIncrement,
            onDecrement: onDecrement,
          ),
      ],
    );
  }
}

class _GridHeader extends StatelessWidget {
  const _GridHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.lg, AppTokens.sm, AppTokens.lg, AppTokens.xs),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('DENOMINATION', style: style)),
          Expanded(
            flex: 5,
            child: Text('COUNT', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 4,
            child: Text('SUBTOTAL', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _DenominationRow extends StatefulWidget {
  const _DenominationRow({
    super.key,
    required this.denomination,
    required this.count,
    required this.ocr,
    required this.isLast,
    required this.enabled,
    required this.onSetCount,
    required this.onIncrement,
    required this.onDecrement,
  });

  final Denomination denomination;
  final int count;
  final bool ocr;
  final bool isLast;
  final bool enabled;
  final void Function(Denomination, int) onSetCount;
  final void Function(Denomination) onIncrement;
  final void Function(Denomination) onDecrement;

  @override
  State<_DenominationRow> createState() => _DenominationRowState();
}

class _DenominationRowState extends State<_DenominationRow> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.count == 0 ? '' : '${widget.count}');
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _DenominationRow old) {
    super.didUpdateWidget(old);
    // Keep the field in sync when the count changes externally (steppers, OCR
    // merge) without fighting the user while they're actively typing.
    if (!_focus.hasFocus && widget.count != old.count) {
      final next = widget.count == 0 ? '' : '${widget.count}';
      if (_controller.text != next) {
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = widget.denomination;
    final count = widget.count;
    final isZero = count == 0;
    final subtotal = Money.fromCentavos(d.centavos * count);

    final tint = widget.ocr
        ? scheme.tertiaryContainer.withValues(alpha: 0.30)
        : Colors.transparent;

    final labelColor = isZero && !widget.ocr
        ? scheme.onSurfaceVariant.withValues(alpha: 0.7)
        : scheme.onSurface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: tint,
        border: Border(
          bottom: widget.isLast
              ? BorderSide.none
              : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.lg, vertical: AppTokens.sm),
      child: Row(
        children: [
          // Denomination + OCR badge.
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    d.label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: labelColor,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.ocr) const _OcrBadge(),
              ],
            ),
          ),
          // Stepper.
          Expanded(
            flex: 5,
            child: _CountStepper(
              controller: _controller,
              focusNode: _focus,
              count: count,
              enabled: widget.enabled,
              semanticLabel: d.label,
              onMinus: () => widget.onDecrement(d),
              onPlus: () => widget.onIncrement(d),
              onChanged: (n) => widget.onSetCount(d, n),
            ),
          ),
          // Live subtotal — right-aligned, tabular figures, animated on change.
          Expanded(
            flex: 4,
            child: Text(
              subtotal.format(),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: isZero ? scheme.onSurfaceVariant : scheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ).animate(key: ValueKey(subtotal.centavos)).fadeIn(
                  duration: 180.ms,
                  curve: Curves.easeOut,
                ),
          ),
        ],
      ),
    );
  }
}

class _OcrBadge extends StatelessWidget {
  const _OcrBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: 'Pre-filled from photo — please verify',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: ShapeDecoration(
            color: scheme.tertiary.withValues(alpha: 0.18),
            shape: const StadiumBorder(),
          ),
          child: Text(
            'OCR',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.tertiary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  fontSize: 10,
                ),
          ),
        ),
      ),
    );
  }
}

class _CountStepper extends StatelessWidget {
  const _CountStepper({
    required this.controller,
    required this.focusNode,
    required this.count,
    required this.enabled,
    required this.semanticLabel,
    required this.onMinus,
    required this.onPlus,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int count;
  final bool enabled;
  final String semanticLabel;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepButton(
          icon: Icons.remove_rounded,
          tooltip: 'Decrease $semanticLabel count',
          onPressed: enabled && count > 0 ? onMinus : null,
        ),
        SizedBox(
          width: 56,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(
                signed: false, decimal: false),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
            decoration: InputDecoration(
              isDense: true,
              hintText: '0',
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              fillColor: scheme.surface,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.sm),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.sm),
                borderSide: BorderSide(color: scheme.primary, width: 1.6),
              ),
            ),
            onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
          ),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          tooltip: 'Increase $semanticLabel count',
          onPressed: enabled ? onPlus : null,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      // 48dp minimum target preserved by IconButton's default constraints.
      iconSize: 20,
      style: IconButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        foregroundColor: scheme.onSurface,
        disabledForegroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.sm)),
      ),
      icon: Icon(icon),
    );
  }
}
