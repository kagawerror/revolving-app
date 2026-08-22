import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../domain/fund.dart';
import 'balance_impact.dart';

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
/// INTEGRATION (caller, in admin_home_body):
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

  // --- Change detection -----------------------------------------------------
  //
  // Only the fund name is editable on a saved fund. Budget and the low-balance
  // threshold are shown read-only (the budget edit would shift real money via
  // adjustBudget), so the name is the sole source of a change here.

  String get _trimmedName => _name.text.trim();

  bool get _nameChanged =>
      _trimmedName.isNotEmpty && _trimmedName != widget.fund.name;

  bool get _hasChanges => _nameChanged;
  bool get _canSave => _hasChanges && !_saving;

  Future<void> _save() async {
    if (!_canSave) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    // Name is the only editable field; budget and threshold stay untouched.
    final submission = EditFundSubmission(name: _trimmedName);

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
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _canSave ? _save() : null,
                decoration: const InputDecoration(
                  labelText: 'Fund name',
                  prefixIcon: Icon(Icons.savings_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppTokens.lg),
              // Budget and the low-balance threshold are locked once a fund is
              // saved — changing the budget would move real money. They stay
              // visible (read-only) for reference; only the name can change.
              TextFormField(
                controller: _budget,
                enabled: false,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Budget (₱)',
                  prefixIcon: Icon(Icons.payments_outlined),
                  suffixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                  helperText: "Can't be changed after the fund is created",
                ),
              ),
              const SizedBox(height: AppTokens.sm),
              BalanceImpact(
                currentAvailable: widget.fund.availableBalance,
                deltaCentavos: null,
                lowThreshold: widget.fund.lowBalanceThreshold,
              ),
              const SizedBox(height: AppTokens.lg),
              TextFormField(
                controller: _pct,
                enabled: false,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Low-balance alert (%)',
                  prefixIcon: Icon(Icons.notifications_active_outlined),
                  suffixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                  helperText: "Can't be changed after the fund is created",
                ),
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
