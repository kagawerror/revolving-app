import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/error/result.dart';
import '../../../core/ids.dart';
import '../../sync/domain/outbox_entry.dart';
import '../../sync/domain/release_intent.dart';
import '../../sync/domain/release_payload.dart';
import '../../sync/presentation/sync_providers.dart';
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

    // Connectivity decides whether we commit online (transaction) or capture
    // locally (queue). Loading/unknown is treated as OFFLINE — safer to queue
    // than to block the incharge on an unreachable server.
    final online = ref.read(connectivityProvider).valueOrNull ?? false;

    // Step 1 — confirm. When offline, the body shows the OPTIMISTIC post-release
    // balance (server balance minus pending local releases, which already
    // include in-flight captures) rather than the raw server balance.
    final optimisticBalance =
        ref.read(optimisticFundBalanceProvider(request.fundId));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(online ? Icons.payments_rounded : Icons.cloud_off_rounded),
        title: const Text('Release cash?'),
        content: Text(
          online
              ? 'This will deduct ${request.amount.format()} from the fund and '
                  'pay out to ${request.beneficiaryName}. You will capture a '
                  'release photo and the recipient\'s signature next. This '
                  'cannot be undone.'
              : 'You\'re offline — the ${request.amount.format()} cash release '
                  'to ${request.beneficiaryName} will be recorded on your '
                  'device and synced when you reconnect. You will capture a '
                  'release photo and the recipient\'s signature next. The fund '
                  'balance shown (${_formatCentavos(optimisticBalance.centavos)}) '
                  'reflects this pending release.',
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

    // Step 4 + 5 — capture proof/signature, then commit. The path branches on
    // connectivity: online uploads both images then runs the release
    // transaction; offline saves both images locally and records the release on
    // device (NO fund deduction — the optimistic balance provider reflects it;
    // the server transaction debits exactly once on replay).
    state = true;
    try {
      final result = await commitCaptured(
        request: request,
        actorUid: actorUid,
        proofBytes: proofBytes,
        signatureBytes: signatureBytes,
        online: online,
      );
      if (!context.mounted) return result.isOk;
      if (result.showOnError(context)) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(online
                ? 'Release recorded with signature'
                : 'Release saved on your device — will sync when you reconnect'),
          ));
        return true;
      }
      return false;
    } finally {
      state = false;
    }
  }

  /// Connectivity-branched commit for ALREADY-captured proof + signature bytes.
  /// Exposed for testing so the commit branch (online release transaction vs.
  /// offline local capture + outbox enqueue) can be exercised deterministically
  /// without driving the real camera/signature-pad UI (whose PNG rasterization
  /// is non-deterministic headlessly — see release_flow_controller_test.dart).
  /// The UI flow (dialog/cancel guards) is covered separately by [run]'s tests.
  @visibleForTesting
  Future<Result<void>> commitCaptured({
    required FundRequest request,
    required String actorUid,
    required Uint8List proofBytes,
    required Uint8List signatureBytes,
    required bool online,
  }) {
    // Idempotency id for the replay path. Reuse an existing id (e.g. a retried
    // offline release) so a re-capture stays the same logical release.
    final clientReleaseId = request.clientReleaseId ?? newClientId();
    return online
        ? _commitOnline(
            request: request,
            actorUid: actorUid,
            proofBytes: proofBytes,
            signatureBytes: signatureBytes,
            clientReleaseId: clientReleaseId,
          )
        : _commitOffline(
            request: request,
            actorUid: actorUid,
            proofBytes: proofBytes,
            signatureBytes: signatureBytes,
            clientReleaseId: clientReleaseId,
          );
  }

  /// ONLINE: upload proof + signature, then run the release transaction. An
  /// upload failure is returned as an [Err] so the single `showOnError` path in
  /// [run] surfaces it — no fund deduction happens on a failed capture.
  Future<Result<void>> _commitOnline({
    required FundRequest request,
    required String actorUid,
    required Uint8List proofBytes,
    required Uint8List signatureBytes,
    required String clientReleaseId,
  }) async {
    final proofResult =
        await ref.read(cloudinaryUploaderProvider).uploadJpeg(proofBytes);
    final proofUrl = proofResult.valueOrNull;
    if (proofUrl == null) {
      return Err(proofResult.failureOrNull!);
    }
    final signatureResult =
        await ref.read(signatureUploadProvider)(signatureBytes);
    final signatureUrl = signatureResult.valueOrNull;
    if (signatureUrl == null) {
      return Err(signatureResult.failureOrNull!);
    }
    return ref.read(requestRepositoryProvider).release(
          request: request,
          actorUid: actorUid,
          releaseProofUrl: proofUrl,
          releaseSignatureUrl: signatureUrl,
          clientReleaseId: clientReleaseId,
        );
  }

  /// OFFLINE: save both images locally (both mandatory — same as online), record
  /// the release on device WITHOUT debiting the fund, and enqueue a release
  /// outbox entry whose payload is built through [ReleasePayload.encode].
  Future<Result<void>> _commitOffline({
    required FundRequest request,
    required String actorUid,
    required Uint8List proofBytes,
    required Uint8List signatureBytes,
    required String clientReleaseId,
  }) async {
    // Both images are mandatory offline too — reject (and queue nothing) if
    // either save fails.
    final store = ref.read(localImageStoreProvider);
    final proofSave = await store.save(proofBytes, suffix: '.jpg');
    final proofPath = proofSave.valueOrNull;
    if (proofPath == null) {
      return Err(proofSave.failureOrNull!);
    }
    final signatureSave = await store.save(signatureBytes, suffix: '.png');
    final signaturePath = signatureSave.valueOrNull;
    if (signaturePath == null) {
      await store.deleteQuietly(proofPath);
      return Err(signatureSave.failureOrNull!);
    }

    // Record the release on-device (plain update, no fund deduction).
    final captured = await ref.read(requestRepositoryProvider).captureLocalRelease(
          request: request,
          clientReleaseId: clientReleaseId,
          actorUid: actorUid,
        );
    if (captured.failureOrNull != null) {
      await store.deleteQuietly(proofPath);
      await store.deleteQuietly(signaturePath);
      return captured;
    }

    // Enqueue the release for Phase-5 replay. Payload is canonical via
    // ReleasePayload; clientActionId == clientReleaseId for idempotent dedupe.
    final intent = ReleaseIntent(
      requestId: request.id,
      fundId: request.fundId,
      companyId: request.companyId,
      amount: request.amount,
      clientReleaseId: clientReleaseId,
      localProofPath: proofPath,
      localSignaturePath: signaturePath,
    );
    final entry = OutboxEntry(
      id: clientReleaseId,
      kind: OutboxKind.release,
      companyId: request.companyId,
      entityId: request.id,
      clientActionId: clientReleaseId,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
      localImagePaths: [proofPath, signaturePath],
      payload: ReleasePayload.encode(intent),
    );
    final enqueued = await ref.read(outboxStoreProvider).enqueue(entry);
    if (enqueued.failureOrNull != null) return enqueued;
    return const Ok(null);
  }

  /// Formats signed centavos (the optimistic balance may be negative) as a peso
  /// string for display in the offline confirmation dialog.
  String _formatCentavos(int centavos) {
    final pesos = centavos / 100;
    return NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(pesos);
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
