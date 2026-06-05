import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/fund.dart';
import '../../requests/domain/fund_request.dart';
import 'replenishment_providers.dart';

/// Popup for the incharge to pick which released requests to replenish, then
/// submit them for approval in one tap. Pops `true` on a successful submit so
/// the caller can show the success overlay; stays open (with a snackbar) on
/// failure. [releasable] is the already-filtered released-unreplenished list.
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
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Money get _total {
    var sum = Money.zero;
    for (final r in widget.releasable) {
      if (_selected.contains(r.id)) sum += r.amount;
    }
    return sum;
  }

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null || _selected.isEmpty) return;
    setState(() => _busy = true);
    final res = await ref.read(replenishmentRepositoryProvider).createAndSubmit(
          fundId: widget.fund.id,
          requestIds: _selected.toList(),
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
                        for (final r in widget.releasable)
                          CheckboxListTile(
                            dense: true,
                            value: _selected.contains(r.id),
                            onChanged: _busy
                                ? null
                                : (v) => setState(() {
                                      if (v ?? false) {
                                        _selected.add(r.id);
                                      } else {
                                        _selected.remove(r.id);
                                      }
                                    }),
                            title: Text(r.beneficiaryName),
                            subtitle: Text(
                              r.purpose,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            secondary: Text(
                              r.amount.format(),
                              style: textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
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
          onPressed: (_busy || _selected.isEmpty) ? null : _submit,
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
}
