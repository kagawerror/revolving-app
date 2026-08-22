import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/validation/rejection_remarks.dart';
import '../../domain/fund_request.dart';

/// Reject-reason collector for a request whose cash was NEVER released — the
/// incharge's escape hatch for one created (or acted on) by mistake while it
/// still sits in the release worklist.
///
/// The sheet IS the confirmation step (no second dialog): it names the amount
/// and beneficiary being cancelled, states plainly that **no cash is deducted**
/// — the one thing an incharge worries about when cancelling — and requires a
/// reason before the destructive button enables.
///
/// The reason gate is [validateRejectionRemarks], the same rule the repository
/// re-checks before writing, so a valid-looking submit here can never be
/// refused server-side for a different reason than the one shown live.
///
/// Returns the trimmed reason on confirm, or `null` on cancel/dismiss.
class RejectRequestSheet extends StatefulWidget {
  const RejectRequestSheet({super.key, required this.request});

  final FundRequest request;

  static Future<String?> show(BuildContext context, FundRequest request) =>
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
          child: RejectRequestSheet(request: request),
        ),
      );

  @override
  State<RejectRequestSheet> createState() => _RejectRequestSheetState();
}

class _RejectRequestSheetState extends State<RejectRequestSheet> {
  final _controller = TextEditingController();

  /// Live validation message for the current input, or null when acceptable.
  String? _error;

  /// True only once the user has typed something — keeps the field from
  /// flashing a "required" error before they have had a chance to type.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_revalidate);
    _error = validateRejectionRemarks(_controller.text);
  }

  void _revalidate() {
    final next = validateRejectionRemarks(_controller.text);
    if (next != _error || !_touched) {
      setState(() {
        _error = next;
        _touched = true;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_revalidate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final r = widget.request;
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
                  child: Text('Reject this request',
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.sm),
            // The reassuring, load-bearing line — the mirror image of the
            // dispute sheet's warning. Cancelling here is safe precisely
            // because the cash never left the fund.
            Container(
              padding: const EdgeInsets.all(AppTokens.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: AppTokens.brField,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.savings_rounded,
                      size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: AppTokens.sm),
                  Expanded(
                    child: Text(
                      'No cash will be deducted from the fund. The '
                      '${r.amount.format()} for ${r.beneficiaryName} was never '
                      'released, so rejecting cancels the request without '
                      'moving any money.',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.md),
            Text(
              'This cannot be undone — a rejected request stays rejected. '
              'Create a new request if the spend is still needed.',
              style: textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppTokens.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 280,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: 'Reason for rejecting',
                hintText: 'e.g. created by mistake — duplicate of R-1042',
                // Only surface the error once they have typed, so the sheet
                // doesn't open shouting at them.
                errorText: _touched ? _error : null,
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
                    child: const Text('Keep request'),
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
                    icon: const Icon(Icons.cancel_rounded, size: 18),
                    label: const Text('Reject request'),
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
