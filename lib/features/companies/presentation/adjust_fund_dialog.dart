import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../domain/fund.dart';
import 'balance_impact.dart';

/// Pure, testable seam for an adjust-fund submission. Holds the user's choices
/// in their authoritative form (a [Money] magnitude + direction) and derives the
/// single signed integer the repository actually applies. The coder unit-tests
/// [signedDeltaCentavos] directly — no widget needed.
///
///   isDeduction=false, amount=₱500 => signedDeltaCentavos = +50000
///   isDeduction=true,  amount=₱500 => signedDeltaCentavos = -50000
@immutable
class AdjustFundSubmission {
  const AdjustFundSubmission({
    required this.isDeduction,
    required this.amount,
    required this.reason,
  });

  final bool isDeduction;
  final Money amount;
  final String reason;

  int get signedDeltaCentavos =>
      isDeduction ? -amount.centavos : amount.centavos;

  /// One-line human summary reused by both the confirm dialog and any audit
  /// note: "Add ₱500.00 · Reason: …" / "Deduct ₱500.00 · Reason: …".
  String get summary {
    final verb = isDeduction ? 'Deduct' : 'Add';
    final sign = isDeduction ? '−' : '+';
    return '$verb $sign${amount.format()} · Reason: $reason';
  }
}

/// Opens the Adjust-fund dialog for [fund].
///
/// [onSubmit] performs the async repository write and returns `true` on success
/// (dialog closes) or `false` on failure (dialog stays open, controls
/// re-enable for retry) — the same async-submit contract as
/// [showEditFundDialog]. Resolves to the committed [AdjustFundSubmission] on
/// success, or `null` if cancelled.
///
/// INTEGRATION (caller):
///   final done = await showAdjustFundDialog(
///     context,
///     fund: fund,
///     onSubmit: (s) async {
///       final me = ref.read(currentUserProvider).valueOrNull;
///       if (me == null) return false;
///       final res = await ref.read(fundRepositoryProvider).adjustBalance(
///             fundId: fund.id,
///             signedDeltaCentavos: s.signedDeltaCentavos,
///             reason: s.reason,
///             actorUid: me.uid,
///             actorRole: me.role,
///           );
///       if (!context.mounted) return false;
///       return res.showOnError(context); // true on Ok, snackbar on Err
///     },
///   );
Future<AdjustFundSubmission?> showAdjustFundDialog(
  BuildContext context, {
  required Fund fund,
  required Future<bool> Function(AdjustFundSubmission submission) onSubmit,
}) {
  return showDialog<AdjustFundSubmission>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AdjustFundDialog(fund: fund, onSubmit: onSubmit),
  );
}

class _AdjustFundDialog extends StatefulWidget {
  const _AdjustFundDialog({required this.fund, required this.onSubmit});

  final Fund fund;
  final Future<bool> Function(AdjustFundSubmission submission) onSubmit;

  @override
  State<_AdjustFundDialog> createState() => _AdjustFundDialogState();
}

class _AdjustFundDialogState extends State<_AdjustFundDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reason = TextEditingController();

  bool _isDeduction = false;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  // --- Derived values -------------------------------------------------------

  /// Parsed amount in centavos, or `null` when the field is empty/invalid.
  /// Routes pesos through [Money.fromPesos] (human input) then reads centavos.
  int? get _amountCentavos {
    final pesos = double.tryParse(_amount.text.trim());
    if (pesos == null || pesos <= 0) return null;
    return Money.fromPesos(pesos).centavos;
  }

  /// Signed delta for the live preview, or `null` until a positive amount is
  /// entered. Drives [BalanceImpact].
  int? get _signedDelta {
    final c = _amountCentavos;
    if (c == null) return null;
    return _isDeduction ? -c : c;
  }

  /// A deduction is only legal while it doesn't push the balance below ₱0.
  bool get _wouldOverdraw {
    final c = _amountCentavos;
    if (c == null || !_isDeduction) return false;
    return c > widget.fund.availableBalance.centavos;
  }

  bool get _canSubmit =>
      !_saving && _amountCentavos != null && !_wouldOverdraw;

  String get _maxDeductibleLabel =>
      widget.fund.availableBalance.format();

  // --- Submit flow ----------------------------------------------------------

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final submission = AdjustFundSubmission(
      isDeduction: _isDeduction,
      amount: Money.fromCentavos(_amountCentavos!),
      reason: _reason.text.trim(),
    );

    // House rule: every money mutation passes through a confirm step.
    final confirmed = await _confirm(submission);
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final ok = await widget.onSubmit(submission);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(submission);
    } else {
      setState(() => _saving = false); // stay open, re-enable for retry
    }
  }

  Future<bool?> _confirm(AdjustFundSubmission s) {
    final scheme = Theme.of(context).colorScheme;
    final tone = s.isDeduction ? scheme.error : scheme.tertiary;
    final projected = Money.fromCentavos(
      (widget.fund.availableBalance.centavos + s.signedDeltaCentavos)
          .clamp(0, 1 << 62),
    );

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: AppTokens.brCard),
        icon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.16),
            borderRadius: AppTokens.brField,
          ),
          child: Icon(
            s.isDeduction
                ? Icons.remove_circle_outline_rounded
                : Icons.add_circle_outline_rounded,
            color: tone,
            semanticLabel: s.isDeduction ? 'Deduct' : 'Add',
          ),
        ),
        title: Text(s.isDeduction ? 'Confirm deduction' : 'Confirm addition'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.isDeduction
                  ? 'You are about to deduct cash from this fund.'
                  : 'You are about to add cash to this fund.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppTokens.md),
            _ConfirmRow(
              label: 'Adjustment',
              value:
                  '${s.isDeduction ? '−' : '+'}${s.amount.format()}',
              valueColor: tone,
            ),
            const SizedBox(height: AppTokens.sm),
            _ConfirmRow(
              label: 'New balance',
              value: projected.format(),
            ),
            const SizedBox(height: AppTokens.md),
            Text(
              'Reason',
              style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 2),
            Text(s.reason, style: Theme.of(ctx).textTheme.bodyMedium),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppTokens.lg,
          0,
          AppTokens.lg,
          AppTokens.lg,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: tone,
              foregroundColor: s.isDeduction
                  ? scheme.onError
                  : scheme.onTertiary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.isDeduction ? 'Deduct cash' : 'Add cash'),
          ),
        ],
      ),
    );
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fund = widget.fund;
    final tone = _isDeduction ? scheme.error : scheme.tertiary;

    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: AppTokens.brCard),
      icon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: AppTokens.brField,
        ),
        child: Icon(
          Icons.tune_rounded,
          color: scheme.onPrimaryContainer,
          semanticLabel: 'Adjust fund',
        ),
      ),
      title: const Text('Adjust fund'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                fund.name,
                style: textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                'Budget is not affected — this only moves available cash.',
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppTokens.lg),

              // Direction selector — the most important control: Add vs Deduct
              // must be unmistakable. Selected segment paints in its tone.
              _DirectionSelector(
                isDeduction: _isDeduction,
                enabled: !_saving,
                onChanged: (deduct) => setState(() {
                  _isDeduction = deduct;
                  // Re-run the amount validator so the overdraw error appears or
                  // clears the instant the direction flips.
                  _formKey.currentState?.validate();
                }),
              ),
              const SizedBox(height: AppTokens.lg),

              TextFormField(
                controller: _amount,
                enabled: !_saving,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Amount (₱)',
                  prefixIcon: Icon(
                    _isDeduction
                        ? Icons.remove_rounded
                        : Icons.add_rounded,
                    color: tone,
                  ),
                  helperText: _isDeduction
                      ? 'Up to $_maxDeductibleLabel available'
                      : 'Cash to add to the fund',
                ),
                validator: (v) {
                  final pesos = double.tryParse((v ?? '').trim());
                  if (pesos == null || pesos <= 0) {
                    return 'Enter an amount greater than ₱0';
                  }
                  if (_isDeduction &&
                      Money.fromPesos(pesos).centavos >
                          fund.availableBalance.centavos) {
                    return 'Cannot exceed available balance '
                        '($_maxDeductibleLabel)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppTokens.lg),

              TextFormField(
                controller: _reason,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                minLines: 1,
                maxLines: 3,
                maxLength: 140,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Why is this adjustment being made?',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'A reason is required'
                    : null,
              ),
              const SizedBox(height: AppTokens.xs),

              // Live consequence preview. Reuses the shared widget so the
              // current → projected story is identical to edit-fund.
              BalanceImpact(
                currentAvailable: fund.availableBalance,
                deltaCentavos: _signedDelta,
                lowThreshold: fund.lowBalanceThreshold,
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppTokens.lg,
        0,
        AppTokens.lg,
        AppTokens.lg,
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _canSubmit ? _submit : null,
          icon: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _isDeduction
                      ? Icons.remove_rounded
                      : Icons.add_rounded,
                ),
          label: Text(
            _saving
                ? 'Applying…'
                : (_isDeduction ? 'Deduct' : 'Add'),
          ),
        ),
      ],
    );
  }
}

/// Material 3 [SegmentedButton] Add / Deduct picker. The selected segment is
/// painted in its semantic tone (Add => tertiary/positive, Deduct =>
/// error/warning) with an icon + label, so the chosen direction is never
/// ambiguous — color is always backed by text.
class _DirectionSelector extends StatelessWidget {
  const _DirectionSelector({
    required this.isDeduction,
    required this.enabled,
    required this.onChanged,
  });

  final bool isDeduction;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = isDeduction ? scheme.error : scheme.tertiary;
    final onTone = isDeduction ? scheme.onError : scheme.onTertiary;

    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: tone,
        selectedForegroundColor: onTone,
        side: BorderSide(color: scheme.outlineVariant),
        minimumSize: const Size(0, 48),
        shape: const RoundedRectangleBorder(borderRadius: AppTokens.brField),
      ),
      segments: const [
        ButtonSegment<bool>(
          value: false,
          icon: Icon(Icons.add_rounded),
          label: Text('Add'),
        ),
        ButtonSegment<bool>(
          value: true,
          icon: Icon(Icons.remove_rounded),
          label: Text('Deduct'),
        ),
      ],
      selected: {isDeduction},
      onSelectionChanged:
          enabled ? (s) => onChanged(s.first) : null,
    );
  }
}

/// Label/value row used in the confirmation summary. Value right-aligned with
/// tabular figures so amounts read cleanly.
class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        Text(
          value,
          textAlign: TextAlign.right,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
