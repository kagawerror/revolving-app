import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_repository.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/release_flow_controller.dart';
import 'package:rev_app/features/requests/presentation/request_providers.dart';
import 'package:rev_app/features/sync/data/local_image_store.dart';
import 'package:rev_app/features/sync/data/outbox_store.dart';
import 'package:rev_app/features/sync/domain/outbox_entry.dart';
import 'package:rev_app/features/sync/domain/release_payload.dart';
import 'package:rev_app/features/sync/presentation/sync_providers.dart';
import 'package:rev_app/services/cloudinary/cloudinary_uploader.dart';

// The dialog / camera / signature-pad UI of `run` is covered by
// release_flow_controller_test.dart (the cancellation branches). The PNG
// rasterization of the real signature pad is non-deterministic headlessly, so
// the COMMIT branch is exercised here through `commitCaptured`, which takes
// already-captured bytes and applies the online/offline decision — the exact
// money/state seam this phase adds.

class _MockRepo extends Mock implements RequestRepository {}

class _MockUploader extends Mock implements CloudinaryUploader {}

class _MockImageStore extends Mock implements LocalImageStore {}

class _MockOutbox extends Mock implements OutboxStore {}

FundRequest _request() => FundRequest(
      id: 'r1',
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: 'Ben',
      amount: Money.fromPesos(100),
      purpose: 'Lunch',
      proofImageUrl: 'https://cdn/p.jpg',
      status: RequestStatus.created,
    );

final _proof = Uint8List.fromList([1, 2, 3]);
final _signature = Uint8List.fromList([4, 5, 6]);

void main() {
  setUpAll(() {
    registerFallbackValue(_request());
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(OutboxEntry(
      id: '',
      kind: OutboxKind.release,
      companyId: '',
      entityId: '',
      clientActionId: '',
      createdAtMillis: 0,
    ));
  });

  ProviderContainer container({
    required _MockRepo repo,
    _MockUploader? uploader,
    _MockImageStore? imageStore,
    _MockOutbox? outbox,
  }) {
    final c = ProviderContainer(overrides: [
      requestRepositoryProvider.overrideWithValue(repo),
      if (uploader != null)
        cloudinaryUploaderProvider.overrideWithValue(uploader),
      if (imageStore != null)
        localImageStoreProvider.overrideWithValue(imageStore),
      if (outbox != null) outboxStoreProvider.overrideWithValue(outbox),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test(
      'online commit uploads both images and calls release(...) with a '
      'clientReleaseId; enqueues NO outbox entry', () async {
    final repo = _MockRepo();
    final uploader = _MockUploader();
    final outbox = _MockOutbox();
    when(() => uploader.uploadJpeg(any()))
        .thenAnswer((_) async => const Ok('https://cdn/proof.jpg'));
    // signatureUploadProvider falls through to uploader.uploadPng by default.
    when(() => uploader.uploadPng(any(),
            folder: any(named: 'folder'), preset: any(named: 'preset')))
        .thenAnswer((_) async => const Ok('https://cdn/sig.png'));
    when(() => repo.release(
          request: any(named: 'request'),
          actorUid: any(named: 'actorUid'),
          releaseProofUrl: any(named: 'releaseProofUrl'),
          releaseSignatureUrl: any(named: 'releaseSignatureUrl'),
          clientReleaseId: any(named: 'clientReleaseId'),
        )).thenAnswer((_) async => const Ok(null));

    final c = container(repo: repo, uploader: uploader, outbox: outbox);
    final res =
        await c.read(releaseFlowControllerProvider.notifier).commitCaptured(
              request: _request(),
              actorUid: 'actor1',
              proofBytes: _proof,
              signatureBytes: _signature,
              online: true,
            );

    expect(res.isOk, isTrue);
    final captured = verify(() => repo.release(
          request: any(named: 'request'),
          actorUid: 'actor1',
          releaseProofUrl: 'https://cdn/proof.jpg',
          releaseSignatureUrl: 'https://cdn/sig.png',
          clientReleaseId: captureAny(named: 'clientReleaseId'),
        )).captured;
    expect(captured.single as String, isNotEmpty); // clientReleaseId present.
    verifyNever(() => repo.captureLocalRelease(
          request: any(named: 'request'),
          clientReleaseId: any(named: 'clientReleaseId'),
          actorUid: any(named: 'actorUid'),
        ));
    verifyNever(() => outbox.enqueue(any()));
  });

  test(
      'offline commit saves both images, calls captureLocalRelease (NOT '
      'release), enqueues a ReleasePayload-encoded entry with clientActionId == '
      'clientReleaseId, and never debits the fund', () async {
    final repo = _MockRepo();
    final uploader = _MockUploader();
    final imageStore = _MockImageStore();
    final outbox = _MockOutbox();
    when(() => imageStore.save(any(), suffix: '.jpg'))
        .thenAnswer((_) async => const Ok('/tmp/proof.jpg'));
    when(() => imageStore.save(any(), suffix: '.png'))
        .thenAnswer((_) async => const Ok('/tmp/sig.png'));
    when(() => repo.captureLocalRelease(
          request: any(named: 'request'),
          clientReleaseId: any(named: 'clientReleaseId'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => const Ok(null));
    when(() => outbox.enqueue(any())).thenAnswer((_) async => const Ok(null));

    final c = container(
        repo: repo, uploader: uploader, imageStore: imageStore, outbox: outbox);
    final res =
        await c.read(releaseFlowControllerProvider.notifier).commitCaptured(
              request: _request(),
              actorUid: 'actor1',
              proofBytes: _proof,
              signatureBytes: _signature,
              online: false,
            );

    expect(res.isOk, isTrue);
    // No Cloudinary upload offline.
    verifyNever(() => uploader.uploadJpeg(any()));
    // Both images saved locally.
    verify(() => imageStore.save(any(), suffix: '.jpg')).called(1);
    verify(() => imageStore.save(any(), suffix: '.png')).called(1);
    // captureLocalRelease, NOT release — the fund is never debited locally.
    final capturedId = verify(() => repo.captureLocalRelease(
          request: any(named: 'request'),
          clientReleaseId: captureAny(named: 'clientReleaseId'),
          actorUid: 'actor1',
        )).captured.single as String;
    verifyNever(() => repo.release(
          request: any(named: 'request'),
          actorUid: any(named: 'actorUid'),
          releaseProofUrl: any(named: 'releaseProofUrl'),
          releaseSignatureUrl: any(named: 'releaseSignatureUrl'),
          clientReleaseId: any(named: 'clientReleaseId'),
        ));
    // Outbox entry: release kind, ReleasePayload-encoded, clientActionId == id.
    final entry =
        verify(() => outbox.enqueue(captureAny())).captured.single as OutboxEntry;
    expect(entry.kind, OutboxKind.release);
    expect(entry.entityId, 'r1');
    expect(entry.clientActionId, capturedId);
    expect(entry.localImagePaths, ['/tmp/proof.jpg', '/tmp/sig.png']);
    final intent = ReleasePayload.decode(entry.payload)!;
    expect(intent.requestId, 'r1');
    expect(intent.fundId, 'f1');
    expect(intent.amount, Money.fromPesos(100));
    expect(intent.clientReleaseId, capturedId);
    expect(intent.localProofPath, '/tmp/proof.jpg');
    expect(intent.localSignaturePath, '/tmp/sig.png');
  });

  test(
      'offline commit with a failed signature save enqueues nothing and never '
      'calls captureLocalRelease', () async {
    final repo = _MockRepo();
    final imageStore = _MockImageStore();
    final outbox = _MockOutbox();
    when(() => imageStore.save(any(), suffix: '.jpg'))
        .thenAnswer((_) async => const Ok('/tmp/proof.jpg'));
    when(() => imageStore.save(any(), suffix: '.png'))
        .thenAnswer((_) async => const Err(UnexpectedFailure('disk full')));
    when(() => imageStore.deleteQuietly(any())).thenAnswer((_) async {});

    final c = container(repo: repo, imageStore: imageStore, outbox: outbox);
    final res =
        await c.read(releaseFlowControllerProvider.notifier).commitCaptured(
              request: _request(),
              actorUid: 'actor1',
              proofBytes: _proof,
              signatureBytes: _signature,
              online: false,
            );

    expect(res.failureOrNull, isNotNull);
    verifyNever(() => repo.captureLocalRelease(
          request: any(named: 'request'),
          clientReleaseId: any(named: 'clientReleaseId'),
          actorUid: any(named: 'actorUid'),
        ));
    verifyNever(() => outbox.enqueue(any()));
  });
}
