import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure_ui.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../sync/presentation/sync_providers.dart';
import '../../domain/fund_request.dart';
import '../../domain/request_status.dart';
import '../release_flow_controller.dart';
import '../request_providers.dart';
import '../request_status_visual.dart';
import 'reject_request_sheet.dart';

/// Trailing action for one request row in the incharge worklist.
///
/// Extracted from the incharge home body so both outcomes of a not-yet-released
/// request can be exercised directly in a widget test, without standing up the
/// whole home screen's provider graph.
///
/// Shows the status pill unless the viewer is a fund custodian (or an admin
/// superuser operating this company) — defense-in-depth mirroring the
/// `isIncharge() || isAdmin()` Firestore rule; the server is still the
/// authority.
class RequestRowAction extends ConsumerWidget {
  const RequestRowAction({super.key, required this.request});

  final FundRequest request;

  /// REJECT BEFORE RELEASE — cancels a request created (or acted on) by
  /// mistake. Offered ONLY at `created`, where the fund has not been touched:
  /// from `released` onward the cash is out and must be reconciled through
  /// replenishment or dispute, never erased. A `conflict` is an already-released
  /// overdraft, so its rejection goes through `resolveConflict` (which
  /// re-validates money) — not here.
  ///
  /// [RejectRequestSheet] is the confirmation: it states that no cash is
  /// deducted and requires a reason before the destructive button enables.
  Future<void> _reject(BuildContext context, WidgetRef ref, String uid) async {
    final reason = await RejectRequestSheet.show(context, request);
    if (reason == null || !context.mounted) return; // cancelled
    final user = ref.read(currentUserProvider).valueOrNull;
    final res = await ref.read(requestRepositoryProvider).rejectBeforeRelease(
          request: request,
          actorUid: uid,
          reason: reason,
          // Display-only denormalization for the approvers' alert row; the
          // reason itself is PII and never reaches a notification. Both are
          // null-safe while the fund stream is still loading.
          actorName: user?.displayName,
          fundName: ref.read(fundByIdProvider(request.fundId)).valueOrNull?.name,
        );
    if (!context.mounted) return;
    if (res.showOnError(context)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request rejected — no funds were deducted.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final canManage = user?.role.canManageFundOrAdmin ?? false;
    if (!canManage) return _statusPill();

    switch (request.status) {
      // Release-first: the incharge releases a freshly created request
      // directly, or cancels it outright if it should never have existed.
      case RequestStatus.created:
        // Pre-warm the fund stream so the display-only fundName is already
        // resolved when the reject lands. Never feeds money or the transition.
        ref.watch(fundByIdProvider(request.fundId));
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RejectIconButton(
              onPressed: () =>
                  unawaited(_reject(context, ref, user!.uid)),
            ),
            const SizedBox(width: AppTokens.sm),
            _releaseButton(context, ref, user!.uid),
          ],
        );
      // A conflicted (overdraft) request is resolved through the same release
      // flow once funds allow.
      case RequestStatus.conflict:
        return _releaseButton(context, ref, user!.uid);
      default:
        return _statusPill();
    }
  }

  Widget _releaseButton(BuildContext context, WidgetRef ref, String uid) =>
      FilledButton.icon(
        onPressed: () => unawaited(
          ref
              .read(releaseFlowControllerProvider.notifier)
              .run(context, request, uid),
        ),
        icon: const Icon(Icons.payments_rounded, size: 18),
        label: const Text('Release'),
      );

  Widget _statusPill() {
    final visual = requestStatusVisual(request.status);
    return StatusPill(
      label: visual.label,
      tone: visual.tone,
      icon: visual.icon,
    );
  }
}

/// Compact, error-toned secondary action beside Release. Icon-only so the row
/// stays readable on a narrow phone, with a tooltip + semantics label carrying
/// the full meaning for screen readers.
class _RejectIconButton extends StatelessWidget {
  const _RejectIconButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Reject request',
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        foregroundColor: scheme.error,
        side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
      ),
      icon: const Icon(Icons.cancel_rounded, size: 18),
    );
  }
}
