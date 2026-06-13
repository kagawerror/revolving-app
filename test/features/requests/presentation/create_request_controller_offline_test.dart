import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_repository.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/create_request_controller.dart';
import 'package:rev_app/features/requests/presentation/request_providers.dart';
import 'package:rev_app/features/sync/data/local_image_store.dart';
import 'package:rev_app/features/sync/data/outbox_store.dart';
import 'package:rev_app/features/sync/domain/outbox_entry.dart';
import 'package:rev_app/features/sync/presentation/sync_providers.dart';
import 'package:rev_app/services/cloudinary/cloudinary_uploader.dart';

class _MockRepo extends Mock implements RequestRepository {}

class _MockUploader extends Mock implements CloudinaryUploader {}

class _MockImageStore extends Mock implements LocalImageStore {}

class _MockOutbox extends Mock implements OutboxStore {}

void main() {
  setUpAll(() {
    registerFallbackValue(FundRequest(
      id: '',
      companyId: '',
      fundId: '',
      createdByUid: '',
      beneficiaryName: '',
      amount: Money.zero,
      purpose: '',
      proofImageUrl: '',
      status: RequestStatus.created,
    ));
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(OutboxEntry(
      id: '',
      kind: OutboxKind.createRequest,
      companyId: '',
      entityId: '',
      clientActionId: '',
      createdAtMillis: 0,
    ));
  });

  Future<ProviderContainer> container({
    required bool online,
    required _MockRepo repo,
    _MockUploader? uploader,
    _MockImageStore? imageStore,
    _MockOutbox? outbox,
  }) async {
    final c = ProviderContainer(overrides: [
      requestRepositoryProvider.overrideWithValue(repo),
      if (uploader != null)
        cloudinaryUploaderProvider.overrideWithValue(uploader),
      if (imageStore != null)
        localImageStoreProvider.overrideWithValue(imageStore),
      if (outbox != null) outboxStoreProvider.overrideWithValue(outbox),
      connectivityProvider.overrideWith((ref) => Stream.value(online)),
    ]);
    addTearDown(c.dispose);
    // Settle the connectivity stream so valueOrNull reflects the override.
    await c.read(connectivityProvider.future);
    return c;
  }

  test('online create uploads to Cloudinary and enqueues NO outbox entry',
      () async {
    final repo = _MockRepo();
    final uploader = _MockUploader();
    final outbox = _MockOutbox();
    when(() => uploader.uploadJpeg(any()))
        .thenAnswer((_) async => const Ok('https://cdn/p.jpg'));
    when(() => repo.create(any())).thenAnswer((_) async => const Ok('r1'));

    final c = await container(
        online: true, repo: repo, uploader: uploader, outbox: outbox);

    final res = await c.read(createRequestControllerProvider.notifier).submit(
          companyId: 'c1',
          fundId: 'f1',
          createdByUid: 'u1',
          beneficiary: 'Ben',
          amount: Money.fromPesos(100),
          purpose: 'x',
          imageBytes: Uint8List.fromList([1, 2, 3]),
        );

    expect(res.valueOrNull, 'r1');
    final created =
        verify(() => repo.create(captureAny())).captured.single as FundRequest;
    expect(created.proofImageUrl, 'https://cdn/p.jpg');
    expect(created.pendingImageRef, isNull);
    verifyNever(() => outbox.enqueue(any()));
  });

  test(
      'offline create saves image locally, creates doc with empty proofImageUrl '
      '+ pendingImageRef, and enqueues a createRequest outbox entry', () async {
    final repo = _MockRepo();
    final uploader = _MockUploader();
    final imageStore = _MockImageStore();
    final outbox = _MockOutbox();
    when(() => imageStore.save(any(), suffix: any(named: 'suffix')))
        .thenAnswer((_) async => const Ok('/tmp/offline/proof.jpg'));
    when(() => repo.create(any())).thenAnswer((_) async => const Ok('r1'));
    when(() => outbox.enqueue(any())).thenAnswer((_) async => const Ok(null));

    final c = await container(
      online: false,
      repo: repo,
      uploader: uploader,
      imageStore: imageStore,
      outbox: outbox,
    );

    final res = await c.read(createRequestControllerProvider.notifier).submit(
          companyId: 'c1',
          fundId: 'f1',
          createdByUid: 'u1',
          beneficiary: 'Ben',
          amount: Money.fromPesos(100),
          purpose: 'x',
          imageBytes: Uint8List.fromList([1, 2, 3]),
        );

    expect(res.valueOrNull, 'r1');
    // No Cloudinary upload while offline.
    verifyNever(() => uploader.uploadJpeg(any()));
    // Image persisted locally.
    verify(() => imageStore.save(any(), suffix: '.jpg')).called(1);
    // Doc created with empty proof + a pendingImageRef.
    final created =
        verify(() => repo.create(captureAny())).captured.single as FundRequest;
    expect(created.proofImageUrl, '');
    expect(created.pendingImageRef, isNotNull);
    expect(created.status, RequestStatus.created);
    // Outbox entry enqueued, kind createRequest, carrying the local path.
    final entry =
        verify(() => outbox.enqueue(captureAny())).captured.single as OutboxEntry;
    expect(entry.kind, OutboxKind.createRequest);
    expect(entry.entityId, 'r1');
    expect(entry.localImagePaths, ['/tmp/offline/proof.jpg']);
    expect(entry.payload['localProofPath'], '/tmp/offline/proof.jpg');
  });
}
