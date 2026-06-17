import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/theme/app_tokens.dart';
import '../../auth/presentation/auth_providers.dart';
import 'fund_audit_providers.dart';
import 'widgets/capture_card.dart';
import 'widgets/denomination_grid.dart';
import 'widgets/reconciliation_card.dart';

/// Cash-count capture + live Proof-of-Cash reconciliation.
///
/// Route: `/incharge/audit/new` (companyId + fundId).
class FundAuditCreateScreen extends ConsumerStatefulWidget {
  const FundAuditCreateScreen({
    super.key,
    required this.companyId,
    required this.fundId,
  });

  final String companyId;
  final String fundId;

  @override
  ConsumerState<FundAuditCreateScreen> createState() =>
      _FundAuditCreateScreenState();
}

class _FundAuditCreateScreenState extends ConsumerState<FundAuditCreateScreen> {
  final _noteController = TextEditingController();

  ({String companyId, String fundId}) get _key =>
      (companyId: widget.companyId, fundId: widget.fundId);

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final today = DateFormat('MMMM d, yyyy').format(DateTime.now());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_outline_rounded),
        title: const Text('Save cash count?'),
        content: Text(
          'Save this cash count as of $today?\n\n'
          'This record is final and cannot be edited.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save record'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final res =
        await ref.read(fundAuditControllerProvider(_key).notifier).save();
    if (!mounted) return;
    res.when(
      ok: (auditId) => context.go('/incharge/audit/$auditId'),
      err: (f) => context.showFailure(f),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Defensive role gate — the router gates this, but never surface money
    // capture to a role that can't manage a fund.
    final role = ref.watch(currentUserProvider).valueOrNull?.role;
    final canManage = role?.canManageFund ?? false;
    final isAdmin = role?.isAdmin ?? false;
    if (!canManage && !isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cash Count')),
        body: const _NotAllowed(),
      );
    }

    final ctrl = ref.read(fundAuditControllerProvider(_key).notifier);
    final state = ref.watch(fundAuditControllerProvider(_key));

    if (_noteController.text != state.note) {
      _noteController.value = TextEditingValue(
        text: state.note,
        selection: TextSelection.collapsed(offset: state.note.length),
      );
    }

    final hasPhoto = (state.proofImagePath?.isNotEmpty ?? false) ||
        state.proofImageUrl.isNotEmpty;
    final hasCounts = state.counts.values.any((c) => c > 0);
    final canSave = !state.saving && !state.ocrRunning && hasPhoto && hasCounts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Count'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(
                left: AppTokens.lg, bottom: AppTokens.sm, right: AppTokens.lg),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                state.fundName,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.lg, AppTokens.lg, AppTokens.lg, AppTokens.lg),
              children: [
                CaptureCard(
                  imagePath: state.proofImagePath,
                  ocrRunning: state.ocrRunning,
                  onCapture: () => ctrl.pickPhotoAndOcr(),
                ),
                const SizedBox(height: AppTokens.md),
                _OcrHint(prefilledCount: state.ocrPrefilled.length),
                const SizedBox(height: AppTokens.lg),
                _SectionLabel(
                  text: 'Denomination count',
                  trailing: hasCounts ? null : 'Enter at least one count',
                ),
                const SizedBox(height: AppTokens.xs),
                Card(
                  margin: EdgeInsets.zero,
                  child: DenominationGrid(
                    counts: state.counts,
                    ocrPrefilled: state.ocrPrefilled,
                    enabled: !state.saving,
                    onSetCount: ctrl.setCount,
                    onIncrement: ctrl.increment,
                    onDecrement: ctrl.decrement,
                  ),
                ),
                const SizedBox(height: AppTokens.lg),
                const _SectionLabel(text: 'Note (optional)'),
                const SizedBox(height: AppTokens.xs),
                TextField(
                  controller: _noteController,
                  enabled: !state.saving,
                  maxLines: 3,
                  maxLength: 240,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'e.g. counted with witness, sheet ref #…',
                  ),
                  onChanged: ctrl.setNote,
                ),
                const SizedBox(height: AppTokens.lg),
              ],
            ),
          ),
          // Sticky reconciliation + save action.
          _StickyFooter(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReconciliationCard(outcome: state.outcome),
                const SizedBox(height: AppTokens.md),
                FilledButton.icon(
                  onPressed: canSave ? _save : null,
                  icon: state.saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_rounded),
                  label: Text(state.saving ? 'Saving…' : 'Save cash count'),
                ),
                if (!canSave && !state.saving)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTokens.xs),
                    child: Text(
                      !hasPhoto
                          ? 'Add the count-sheet photo to save'
                          : !hasCounts
                              ? 'Enter at least one denomination count'
                              : '',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyFooter extends StatelessWidget {
  const _StickyFooter({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppTokens.lg,
        AppTokens.md,
        AppTokens.lg,
        AppTokens.md + MediaQuery.of(context).padding.bottom,
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(text, style: Theme.of(context).textTheme.titleMedium),
        if (trailing != null)
          Flexible(
            child: Text(
              trailing!,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
      ],
    );
  }
}

class _OcrHint extends StatelessWidget {
  const _OcrHint({required this.prefilledCount});
  final int prefilledCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = prefilledCount == 0
        ? 'Counts you enter are computed live below. The photo is your proof of count.'
        : '$prefilledCount row${prefilledCount == 1 ? '' : 's'} pre-filled from the photo. '
            'Verify the highlighted rows — every value is editable.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded,
            size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _NotAllowed extends StatelessWidget {
  const _NotAllowed();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: AppTokens.md),
            Text('Only the fund custodian can record a cash count.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
