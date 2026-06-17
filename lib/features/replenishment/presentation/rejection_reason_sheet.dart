import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../domain/rejection_remarks.dart';
import '../domain/replenishment.dart';

/// Rejection-reason collector — a confirmation sheet that REQUIRES a remark
/// before an approver can reject a replenishment report. The incharge reads
/// this remark on the report's detail screen, so the field is validated live
/// against [validateRejectionRemarks] (the single source of truth, also
/// re-checked server-side) and the submit button stays disabled until the
/// remark is acceptable — no silent no-op on an empty/too-short field.
///
/// Returns the trimmed reason on confirm, or `null` on cancel/dismiss.
///
/// Mirrors the proven `DisputeReasonSheet` pattern (keyboard-aware modal,
/// inline guidance, error-toned warning, disabled-until-valid submit).
class RejectionReasonSheet extends StatefulWidget {
  const RejectionReasonSheet({super.key, required this.replenishment});
  final Replenishment replenishment;

  static Future<String?> show(
          BuildContext context, Replenishment replenishment) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Padding(
          // Lift above the keyboard so the field and submit stay visible. Read
          // the inset from the sheet's OWN context (viewInsetsOf) so it tracks
          // the keyboard animating in/out, rather than capturing it once from
          // the launching context.
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: RejectionReasonSheet(replenishment: replenishment),
        ),
      );

  @override
  State<RejectionReasonSheet> createState() => _RejectionReasonSheetState();
}

class _RejectionReasonSheetState extends State<RejectionReasonSheet> {
  final _controller = TextEditingController();

  /// The live validation message for the current input, or null when valid.
  /// Sourced from the shared [validateRejectionRemarks] so the sheet, the
  /// disabled submit, and the server rule all agree.
  String? _error;

  /// True only once the user has typed something — keeps the field from
  /// flashing a "required" error before the approver has had a chance to type.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_revalidate);
  }

  void _revalidate() {
    final next = validateRejectionRemarks(_controller.text);
    final touched = _touched || _controller.text.isNotEmpty;
    if (next != _error || touched != _touched) {
      setState(() {
        _error = next;
        _touched = touched;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final r = widget.replenishment;
    final valid = _error == null;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppTokens.rCard)),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppTokens.lg, AppTokens.md, AppTokens.lg, AppTokens.lg),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle, matching the dispute sheet.
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppTokens.rPill),
                ),
              ),
            ),
            const SizedBox(height: AppTokens.lg),
            Row(
              children: [
                Icon(Icons.cancel_rounded, color: scheme.error),
                const SizedBox(width: AppTokens.sm),
                Expanded(
                  child: Text('Reject replenishment',
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.sm),
            // The honest, load-bearing line: rejecting is final and moves no
            // money. Same copy spirit as the existing reject confirm dialog.
            Container(
              padding: const EdgeInsets.all(AppTokens.md),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: AppTokens.brField,
              ),
              child: Text(
                'This rejects the ${r.total.format()} report. No money moves, '
                'but the decision is final and cannot be undone.',
                style:
                    textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
            const SizedBox(height: AppTokens.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 280,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Reason for rejection',
                hintText: 'e.g. amounts don’t match the receipts',
                helperText:
                    'The incharge will see this. Be specific (at least '
                    '$kMinRejectionRemarksLength characters).',
                helperMaxLines: 2,
                // Only surface the error once the user has engaged with the
                // field, so it guides rather than scolds.
                errorText: _touched ? _error : null,
                errorMaxLines: 2,
              ),
            ),
            const SizedBox(height: AppTokens.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppTokens.md),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                    ),
                    onPressed: valid
                        ? () =>
                            Navigator.of(context).pop(_controller.text.trim())
                        : null,
                    icon: const Icon(Icons.block_rounded, size: 18),
                    label: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
