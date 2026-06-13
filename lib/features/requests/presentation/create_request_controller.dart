import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/ids.dart';
import '../../../core/money/money.dart';
import '../../sync/domain/outbox_entry.dart';
import '../../sync/presentation/sync_providers.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'request_providers.dart';

class CreateRequestController extends Notifier<bool> {
  @override
  bool build() => false; // submitting?

  Future<Result<String>> submit({
    required String companyId,
    required String fundId,
    required String createdByUid,
    required String beneficiary,
    required Money amount,
    required String purpose,
    required Uint8List? imageBytes,
  }) async {
    if (imageBytes == null) {
      return const Err(ValidationFailure('Attach a photo as proof of request.'));
    }
    if (amount == Money.zero) {
      return const Err(ValidationFailure('Enter an amount greater than zero.'));
    }
    // Connectivity gate. When the probe is loading/unknown we treat the device
    // as OFFLINE on purpose: queuing locally is always safe (it surfaces from
    // cache and syncs later), whereas blocking on an upload could strand the
    // incharge. Online is the explicit `true`.
    final online = ref.read(connectivityProvider).valueOrNull ?? false;
    state = true;
    try {
      return online
          ? await _submitOnline(
              companyId: companyId,
              fundId: fundId,
              createdByUid: createdByUid,
              beneficiary: beneficiary,
              amount: amount,
              purpose: purpose,
              imageBytes: imageBytes,
            )
          : await _submitOffline(
              companyId: companyId,
              fundId: fundId,
              createdByUid: createdByUid,
              beneficiary: beneficiary,
              amount: amount,
              purpose: purpose,
              imageBytes: imageBytes,
            );
    } finally {
      state = false;
    }
  }

  /// ONLINE: upload the proof to Cloudinary up front, then create the doc with
  /// the resulting URL. Unchanged from the original single-path behaviour.
  Future<Result<String>> _submitOnline({
    required String companyId,
    required String fundId,
    required String createdByUid,
    required String beneficiary,
    required Money amount,
    required String purpose,
    required Uint8List imageBytes,
  }) async {
    final upload =
        await ref.read(cloudinaryUploaderProvider).uploadJpeg(imageBytes);
    final url = upload.valueOrNull;
    if (url == null) {
      return Err(
          upload.failureOrNull ?? const UnexpectedFailure('Upload failed.'));
    }
    final request = FundRequest(
      id: '',
      companyId: companyId,
      fundId: fundId,
      createdByUid: createdByUid,
      beneficiaryName: beneficiary,
      amount: amount,
      purpose: purpose,
      proofImageUrl: url,
      status: RequestStatus.created,
    );
    return ref.read(requestRepositoryProvider).create(request);
  }

  /// OFFLINE: persist the proof bytes locally, create the doc with an empty
  /// proofImageUrl + a pendingImageRef (the create rule accepts this), and
  /// enqueue a createRequest outbox entry so Phase 5 uploads the image and
  /// backfills the URL. The doc surfaces immediately via the Firestore cache.
  Future<Result<String>> _submitOffline({
    required String companyId,
    required String fundId,
    required String createdByUid,
    required String beneficiary,
    required Money amount,
    required String purpose,
    required Uint8List imageBytes,
  }) async {
    // 1. Save the proof bytes locally for later upload.
    final saved = await ref
        .read(localImageStoreProvider)
        .save(imageBytes, suffix: '.jpg');
    final localPath = saved.valueOrNull;
    if (localPath == null) {
      return Err(saved.failureOrNull ??
          const UnexpectedFailure('Could not save the proof image.'));
    }

    // 2. Mint a client id used both as the pendingImageRef and the outbox
    //    correlation id, then create the doc through the repository (queues in
    //    cache; `create` returns the locally-assigned doc id synchronously).
    final clientId = newClientId();
    final request = FundRequest(
      id: '',
      companyId: companyId,
      fundId: fundId,
      createdByUid: createdByUid,
      beneficiaryName: beneficiary,
      amount: amount,
      purpose: purpose,
      proofImageUrl: '',
      status: RequestStatus.created,
      pendingImageRef: clientId,
    );
    final created = await ref.read(requestRepositoryProvider).create(request);
    final requestId = created.valueOrNull;
    if (requestId == null) {
      // Roll back the orphaned local image; nothing else was written.
      await ref.read(localImageStoreProvider).deleteQuietly(localPath);
      return Err(created.failureOrNull ??
          const UnexpectedFailure('Could not save the request locally.'));
    }

    // 3. Enqueue the createRequest mutation. Payload carries only what Phase 5
    //    needs to upload + backfill the image; amounts/PII never get logged.
    final entry = OutboxEntry(
      id: clientId,
      kind: OutboxKind.createRequest,
      companyId: companyId,
      entityId: requestId,
      clientActionId: clientId,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
      localImagePaths: [localPath],
      payload: {
        'requestId': requestId,
        'companyId': companyId,
        'fundId': fundId,
        'localProofPath': localPath,
      },
    );
    final enqueued = await ref.read(outboxStoreProvider).enqueue(entry);
    if (enqueued.failureOrNull != null) {
      return Err(enqueued.failureOrNull!);
    }
    return Ok(requestId);
  }
}

final createRequestControllerProvider =
    NotifierProvider<CreateRequestController, bool>(CreateRequestController.new);
