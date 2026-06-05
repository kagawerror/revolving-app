import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/fund.dart';
import '../../requests/domain/fund_request.dart';
import '../domain/replenishment.dart';
import 'replenishment_providers.dart';

/// Popup for the incharge to pick released requests to replenish — each Full or
/// Partial (amount + remarks) — and submit them for approval in one tap. Pops
/// `true` on a successful submit so the caller can show the success overlay.
/// [releasable] is the already-filtered released list (remaining > 0).
class ReplenishSelectDialog extends ConsumerStatefulWidget {
  final Fund fund;
  final List<FundRequest> releasable;
  const ReplenishSelectDialog({
    super.key,
    required this.fund,
    required this.releasable,
  });

  @override
  ConsumerState<ReplenishSelectDialog> createState() =>
      _ReplenishSelectDialogState();
}

class _ReplenishSelectDialogState extends ConsumerState<ReplenishSelectDialog> {
  final _selected = <String>{};
  final _partial = <String>{};
  final _amount = <String, String>{}; // requestId -> raw pesos text
  final _remarks = <String, String>{};
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// Parsed partial centavos for a row, or null if blank/invalid.
  int? _partialCentavos(String id) {
    final t = (_amount[id] ?? '').trim();
    if (t.isEmpty) return null;
    final pesos = num.tryParse(t);
    if (pesos == null) return null;
    return (pesos * 100).round();
  }

  bool _rowValid(FundRequest r) {
    if (!_partial.contains(r.id)) return true; // Full is always valid
    final c = _partialCentavos(r.id);
    if (c == null || c <= 0 || c >= r.remaining.centavos) return false;
    return (_remarks[r.id] ?? '').trim().isNotEmpty;
  }

  bool get _canSubmit =>
      !_busy &&
      _selected.isNotEmpty &&
      widget.releasable.where((r) => _selected.contains(r.id)).every(_rowValid);

  Money get _total {
    var sum = Money.zero;
    for (final r in widget.releasable) {
      if (!_selected.contains(r.id)) continue;
      if (_partial.contains(r.id)) {
        final c = _partialCentavos(r.id);
        if (c != null && c > 0 && c < r.remaining.centavos) {
          sum += Money.fromCentavos(c);
        }
      } else {
        sum += r.remaining;
      }
    }
    return sum;
  }

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null || !_canSubmit) return;
    final items = <ReplenishmentItem>[];
    for (final r in widget.releasable) {
      if (!_selected.contains(r.id)) continue;
      if (_partial.contains(r.id)) {
        items.add(ReplenishmentItem(
          requestId: r.id,
          isPartial: true,
          amount: Money.fromCentavos(_partialCentavos(r.id)!),
          remarks: (_remarks[r.id] ?? '').trim(),
        ));
      } else {
        items.add(ReplenishmentItem(
            requestId: r.id, isPartial: false, amount: r.remaining));
      }
    }
    setState(() => _busy = true);
    final res = await ref.read(replenishmentRepositoryProvider).createAndSubmit(
          fundId: widget.fund.id,
          items: items,
          actorUid: user.uid,
          notes: _notes.text.trim(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.showOnError(context)) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final empty = widget.releasable.isEmpty;
    return AlertDialog(
      title: Text('Replenish ${widget.fund.name}'),
      content: SizedBox(
        width: double.maxFinite,
        child: empty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: AppTokens.lg),
                child: Text('No released requests to replenish.'),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final r in widget.releasable) _row(r, textTheme),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Selected: ${_total.format()} • ${_selected.length} item(s)',
                      style: textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: AppTokens.sm),
                  TextField(
                    controller: _notes,
                    enabled: !_busy,
                    decoration:
                        const InputDecoration(labelText: 'Notes (optional)'),
                    maxLines: 2,
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit for approval'),
        ),
      ],
    );
  }

  Widget _row(FundRequest r, TextTheme textTheme) {
    final checked = _selected.contains(r.id);
    final isPartial = _partial.contains(r.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          dense: true,
          value: checked,
          onChanged: _busy
              ? null
              : (v) => setState(() {
                    if (v ?? false) {
                      _selected.add(r.id);
                    } else {
                      _selected.remove(r.id);
                      _partial.remove(r.id);
                    }
                  }),
          title: Text(r.beneficiaryName),
          subtitle: Text(
            r.purpose,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          secondary: Text(
            r.remaining.format(),
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (checked)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTokens.lg, 0, AppTokens.md, AppTokens.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Full')),
                    ButtonSegment(value: true, label: Text('Partial')),
                  ],
                  selected: {isPartial},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() {
                            if (s.first) {
                              _partial.add(r.id);
                            } else {
                              _partial.remove(r.id);
                            }
                          }),
                ),
                if (isPartial) ...[
                  const SizedBox(height: AppTokens.sm),
                  TextField(
                    enabled: !_busy,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    decoration: InputDecoration(
                      labelText: 'Partial amount',
                      helperText: 'Less than ${r.remaining.format()}',
                    ),
                    onChanged: (v) => setState(() => _amount[r.id] = v),
                  ),
                  const SizedBox(height: AppTokens.xs),
                  TextField(
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'Remarks'),
                    onChanged: (v) => setState(() => _remarks[r.id] = v),
                  ),
                ],
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}
