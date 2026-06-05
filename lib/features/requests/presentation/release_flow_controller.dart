import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/error/failure_ui.dart';
import '../domain/fund_request.dart';
import 'request_providers.dart';
import 'widgets/signature_capture_screen.dart';

/// Orchestrates the multi-step cash-release flow for one request:
///   1. "Release cash?" confirmation dialog.
///   2. Capture a release proof photo (camera).
///   3. Capture the recipient signature (full-screen pad).
///   4. Upload BOTH images (proof + signature) before any Firestore write.
///   5. Commit the release transaction with both URLs.
///
/// The flag held by [releaseFlowControllerProvider] is a simple app-wide busy
/// marker; per-row in-flight UX stays in the calling widgets (they own their
/// own `_releasing` flags so each row disables independently).
///
/// Returns `true` only when cash was released. Any cancellation (dialog, photo,
/// signature) returns `false` and shows a "no cash was deducted" reassurance;
/// failures (upload or transaction) surface via the failure->UI mapping.
class ReleaseFlowController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<bool> run(
    BuildContext context,
    FundRequest request,
    String actorUid,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    // Step 1 — confirm.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.payments_rounded),
        title: const Text('Release cash?'),
        content: Text(
          'This will deduct ${request.amount.format()} from the fund and pay '
          'out to ${request.beneficiaryName}. You will capture a release photo '
          'and the recipient\'s signature next. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return _cancelled(messenger);
    }

    // Step 2 — release proof photo (camera, mandatory).
    final proofBytes = await ref
        .read(imagePickCompressProvider)
        .pick(source: ImageSource.camera);
    if (proofBytes == null) return _cancelled(messenger);
    if (!context.mounted) return false;

    // Step 3 — recipient signature (full-screen pad, mandatory).
    final signatureBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        fullscreenDialog: true,
        builder: (_) => SignatureCaptureScreen(
          recipientName: request.beneficiaryName,
          requestTitle: request.purpose,
          amount: request.amount,
        ),
      ),
    );
    if (signatureBytes == null) return _cancelled(messenger);

    // Step 4 — upload BOTH before any Firestore write. If either upload fails,
    // surface it and abort: no fund deduction on a failed capture.
    state = true;
    try {
      final proofResult =
          await ref.read(cloudinaryUploaderProvider).uploadJpeg(proofBytes);
      final proofUrl = proofResult.valueOrNull;
      if (proofUrl == null) {
        if (context.mounted) context.showFailure(proofResult.failureOrNull!);
        return false;
      }

      final signatureResult =
          await ref.read(signatureUploadProvider)(signatureBytes);
      final signatureUrl = signatureResult.valueOrNull;
      if (signatureUrl == null) {
        if (context.mounted) {
          context.showFailure(signatureResult.failureOrNull!);
        }
        return false;
      }

      // Step 5 — commit.
      final result = await ref.read(requestRepositoryProvider).release(
            request: request,
            actorUid: actorUid,
            releaseProofUrl: proofUrl,
            releaseSignatureUrl: signatureUrl,
          );
      if (!context.mounted) return result.isOk;
      if (result.showOnError(context)) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text('Release recorded with signature'),
          ));
        return true;
      }
      return false;
    } finally {
      state = false;
    }
  }

  bool _cancelled(ScaffoldMessengerState messenger) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('Release cancelled — no cash was deducted'),
      ));
    return false;
  }
}

final releaseFlowControllerProvider =
    NotifierProvider<ReleaseFlowController, bool>(ReleaseFlowController.new);
