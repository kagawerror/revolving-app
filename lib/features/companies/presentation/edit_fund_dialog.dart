import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../domain/fund.dart';

/// Result of an Edit-fund submission, handed back to the caller so it can run
/// the two distinct repository calls the architect specified:
///   - [updateDetails] (name + threshold) and/or
///   - [adjustBudget]  (new budget, with the same delta applied to balance).
/// Only the parts that actually changed are non-null, so the caller can skip
/// no-op writes.
class EditFundSubmission {
  const EditFundSubmission({
    this.name,
    this.lowBalanceThresholdPct,
    this.newBudget,
  });

  /// Non-null only when name and/or threshold changed (one [updateDetails] call).
  final String? name;
  final int? lowBalanceThresholdPct;

  /// Non-null only when the budget changed (one [adjustBudget] call). In pesos
  /// already converted to [Money]; centavos are authoritative under the hood.
  final Money? newBudget;

  bool get touchesDetails =>
      name != null || lowBalanceThresholdPct != null;
  bool get touchesBudget => newBudget != null;
}

/// Prefilled "Edit fund" dialog mirroring [showAddCompanyDialog]'s async-submit
/// contract: [onSubmit] performs the async write(s) and returns `true` on
/// success (dialog closes) or `false` on failure (dialog stays open, buttons
/// re-enable for retry). Returns the new name on success, or `null` if
/// cancelled.
///
/// INTEGRATION (caller, in admin_home_screen):
///   onSubmit: (s) async {
///     if (s.touchesBudget) {
///       final r = await ref.read(fundRepositoryProvider).adjustBudget(
///             fundId: fund.id,
///             newBudget: s.newBudget!,
///             actorUid: currentUser.uid,
///             note: 'Admin budget edit',
///           );
///       if (!context.mounted || !r.showOnError(context)) return false;
///     }
///     if (s.touchesDetails) {
///       final r = await ref.read(fundRepositoryProvider).updateDetails(
///             fundId: fund.id,
///             name: s.name ?? fund.name,
///             lowBalanceThresholdPct:
///                 s.lowBalanceThresholdPct ?? fund.lowBalanceThresholdPct,
///           );
///       if (!context.mounted || !r.showOnError(context)) return false;
///     }
///     return true;
///   }
Future<String?> showEditFundDialog(
  BuildContext context, {
  required Fund fund,
  required Future<bool> Function(EditFundSubmission submission) onSubmit,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EditFundDialog(fund: fund, onSubmit: onSubmit),
  );
}

class _EditFundDialog extends StatefulWidget {
  const _EditFundDialog({required this.fund, required this.onSubmit});
  final Fund fund;
  final Future<bool> Function(EditFundSubmission submission) onSubmit;
  @override
  State<_EditFundDialog> createState() => _EditFundDialogState();
}

class _EditFundDialogState extends State<_EditFundDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _budget;
  late final TextEditingController _pct;
  bool _saving = false;

  /// Pesos string the dialog opened with, so we can detect a real change and
  /// reconstruct centavos for an exact no-change comparison.
  late final int _originalBudgetCentavos;

  @override
  void initState() {
    super.initState();
    final f = widget.fund;
    _originalBudgetCentavos = f.originalBudget.centavos;
    _name = TextEditingController(text: f.name);
    // Whole-peso prefill when the budget is whole; otherwise two decimals.
    _budget = TextEditingController(text: _pesosString(_originalBudgetCentavos));
    _pct = TextEditingController(text: f.lowBalanceThresholdPct.toString());
  }

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    _pct.dispose();
    super.dispose();
  }

  static String _pesosString(int centavos) {
    final pesos = centavos / 100;
    return pesos == pesos.roundToDouble()
        ? pesos.round().toString()
        : pesos.toStringAsFixed(2);
  }

  // --- Parsed current field values -----------------------------------------

  String get _trimmedName => _name.text.trim();

  /// New budget centavos parsed from the field, or null if blank/invalid.
  int? get _parsedBudgetCentavos {
    final n = num.tryParse(_budget.text.trim());
    if (n == null || n < 0) return null;
    return Money.fromPesos(n).centavos;
  }

  int? get _parsedPct {
    final n = int.tryParse(_pct.text.trim());
    if (n == null || n < 1 || n > 100) return null;
    return n;
  }

  // --- Change detection -----------------------------------------------------

  bool get _nameChanged =>
      _trimmedName.isNotEmpty && _trimmedName != widget.fund.name;

  bool get _pctChanged {
    final p = _parsedPct;
    return p != null && p != widget.fund.lowBalanceThresholdPct;
  }

  bool get _budgetChanged {
    final c = _parsedBudgetCentavos;
    return c != null && c != _originalBudgetCentavos;
  }

  /// Signed delta in centavos applied to BOTH original budget and available
  /// balance. Null when the budget field is blank/invalid or unchanged.
  int? get _budgetDeltaCentavos {
    final c = _parsedBudgetCentavos;
    if (c == null) return null;
    return c - _originalBudgetCentavos;
  }

  bool get _hasChanges => _nameChanged || _pctChanged || _budgetChanged;
  bool get _canSave => _hasChanges && !_saving;

  Future<void> _save() async {
    if (!_canSave) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final submission = EditFundSubmission(
      name: _nameChanged ? _trimmedName : null,
      lowBalanceThresholdPct: _pctChanged ? _parsedPct : null,
      newBudget: _budgetChanged
          ? Money.fromCentavos(_parsedBudgetCentavos!)
          : null,
    );

    final ok = await widget.onSubmit(submission);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(submission.name ?? widget.fund.name);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
          Icons.edit_rounded,
          color: scheme.onPrimaryContainer,
          semanticLabel: 'Edit fund',
        ),
      ),
      title: const Text('Edit fund'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                enabled: !_saving,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Fund name',
                  prefixIcon: Icon(Icons.savings_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppTokens.lg),
              TextFormField(
                controller: _budget,
                enabled: !_saving,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Budget (₱)',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (v) {
                  final n = num.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) return 'Enter a positive amount';
                  return null;
                },
              ),
              const SizedBox(height: AppTokens.sm),
              _BalanceImpact(
                currentAvailable: widget.fund.availableBalance,
                deltaCentavos: _budgetDeltaCentavos,
              ),
              const SizedBox(height: AppTokens.lg),
              TextFormField(
                controller: _pct,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _canSave ? _save() : null,
                decoration: const InputDecoration(
                  labelText: 'Low-balance alert (%)',
                  prefixIcon: Icon(Icons.notifications_active_outlined),
                ),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null || n < 1 || n > 100) return 'Enter 1–100';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actionsPadding:
          const EdgeInsets.fromLTRB(AppTokens.lg, 0, AppTokens.lg, AppTokens.lg),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _canSave ? _save : null,
          icon: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

/// Read-only line that always shows the current available balance, and — when
/// the budget field holds a different value — an inline helper explaining that
/// the balance shifts by the same signed delta. This is the key trust feature:
/// the admin sees the consequence before saving.
class _BalanceImpact extends StatelessWidget {
  const _BalanceImpact({
    required this.currentAvailable,
    required this.deltaCentavos,
  });

  final Money currentAvailable;
  final int? deltaCentavos;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final delta = deltaCentavos;
    final hasDelta = delta != null && delta != 0;

    final amountStyle = textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    if (!hasDelta) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Current available balance ${currentAvailable.format()}',
          style: amountStyle,
        ),
      );
    }

    final increase = delta > 0;
    // Available balance may not go negative; clamp the projection for display.
    final projectedCentavos =
        (currentAvailable.centavos + delta).clamp(0, 1 << 62);
    final projected = Money.fromCentavos(projectedCentavos);
    final magnitude = Money.fromCentavos(delta.abs());
    final tone = increase ? scheme.tertiary : scheme.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.md,
        vertical: AppTokens.sm,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: AppTokens.brField,
      ),
      child: Row(
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
                      fontFeatures:
                          const [FontFeature.tabularFigures()],
                    ),
                  ),
                  TextSpan(
                    text:
                        ' (${currentAvailable.format()} → ${projected.format()}).',
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
