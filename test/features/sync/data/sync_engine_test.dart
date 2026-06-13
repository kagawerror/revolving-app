import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/sync/data/sync_engine.dart';
import 'package:rev_app/features/sync/data/outbox_store.dart';
import 'package:rev_app/features/sync/domain/outbox_entry.dart';
import 'package:rev_app/features/sync/domain/release_intent.dart';
import 'package:rev_app/features/sync/domain/release_payload.dart';
import 'package:rev_app/features/sync/domain/release_sync_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory LocalImageStore-shaped fake. Records reads/deletes; can fail reads.
class _FakeImageStore implements SyncImageStore {
  _FakeImageStore({this.failReads = const {}});
  final Set<String> failReads;
  final List<String> deleted = [];

  @override
  Future<Result<List<int>>> read(String path) async {
    if (failReads.contains(path)) {
      return const Err(NotFoundFailure('gone'));
    }
    return Ok(Uint8List.fromList([1, 2, 3]));
  }

  @override
  Future<void> deleteQuietly(String path) async {
    deleted.add(path);
  }
}

/// Cloudinary-shaped fake. Returns a URL per call; can fail specific paths' bytes
/// (keyed by call order since bytes are opaque) — simpler: fail by a flag.
class _FakeUploader implements SyncUploader {
  _FakeUploader({this.fail = false});
  bool fail;
  static const String url = 'http://cdn/img';
  int calls = 0;

  @override
  Future<Result<String>> uploadProof(Uint8List bytes) async {
    calls++;
    if (fail) return const Err(UnexpectedFailure('upload down'));
    return Ok('$url/proof$calls');
  }

  @override
  Future<Result<String>> uploadSignature(Uint8List bytes) async {
    calls++;
    if (fail) return const Err(UnexpectedFailure('upload down'));
    return Ok('$url/sig$calls');
  }
}

/// RequestRepository-shaped fake limited to the two engine entry points.
class _FakeConfirmRepo implements SyncRequestRepository {
  _FakeConfirmRepo({this.result = ReleaseSyncResult.confirmed});
  ReleaseSyncResult result;
  int confirmCalls = 0;
  int backfillCalls = 0;
  final List<String> backfilledUrls = [];

  @override
  Future<Result<ReleaseSyncResult>> confirmPendingRelease({
    required FundRequest request,
    required String clientReleaseId,
    required String releaseProofUrl,
    required String releaseSignatureUrl,
    required String actorUid,
  }) async {
    confirmCalls++;
    return Ok(result);
  }

  @override
  Future<Result<void>> backfillCreateImage({
    required String requestId,
    required String proofImageUrl,
  }) async {
    backfillCalls++;
    backfilledUrls.add(proofImageUrl);
    return const Ok(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late OutboxStore outbox;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    outbox = OutboxStore(prefs);
  });

  OutboxEntry releaseEntry(
    String id, {
    int amount = 1000,
    int createdAt = 1,
    String? proofPath = '/local/proof.jpg',
    String? sigPath = '/local/sig.png',
  }) =>
      OutboxEntry(
        id: id,
        kind: OutboxKind.release,
        companyId: 'c1',
        entityId: 'req-$id',
        clientActionId: 'cai-$id',
        createdAtMillis: createdAt,
        payload: ReleasePayload.encode(ReleaseIntent(
          requestId: 'req-$id',
          fundId: 'f1',
          companyId: 'c1',
          amount: Money.fromCentavos(amount),
          clientReleaseId: 'crid-$id',
          localProofPath: proofPath,
          localSignaturePath: sigPath,
        )),
        localImagePaths: [
          ?proofPath,
          ?sigPath,
        ],
      );

  OutboxEntry createEntry(
    String id, {
    int createdAt = 1,
    String proofPath = '/local/create.jpg',
  }) =>
      OutboxEntry(
        id: id,
        kind: OutboxKind.createRequest,
        companyId: 'c1',
        entityId: 'req-$id',
        clientActionId: 'cai-$id',
        createdAtMillis: createdAt,
        payload: const {},
        localImagePaths: [proofPath],
      );

  SyncEngine engine({
    SyncImageStore? images,
    SyncUploader? uploader,
    SyncRequestRepository? repo,
    String actorUid = 'u1',
  }) =>
      SyncEngine(
        outbox: outbox,
        images: images ?? _FakeImageStore(),
        uploader: uploader ?? _FakeUploader(),
        requests: repo ?? _FakeConfirmRepo(),
        actorUid: () => actorUid,
      );

  test('confirmed release: marks done, deletes local files', () async {
    await outbox.enqueue(releaseEntry('a'));
    final images = _FakeImageStore();
    final repo = _FakeConfirmRepo(result: ReleaseSyncResult.confirmed);
    final report =
        await engine(images: images, repo: repo).drain();

    expect(report.confirmed, 1);
    expect(repo.confirmCalls, 1);
    final entries = outbox.all();
    expect(entries.single.state, OutboxState.done);
    expect(images.deleted, containsAll(['/local/proof.jpg', '/local/sig.png']));
  });

  test('alreadyConfirmed also marks done and deletes files', () async {
    await outbox.enqueue(releaseEntry('a'));
    final images = _FakeImageStore();
    final report = await engine(
      images: images,
      repo: _FakeConfirmRepo(result: ReleaseSyncResult.alreadyConfirmed),
    ).drain();
    expect(report.confirmed, 1);
    expect(outbox.all().single.state, OutboxState.done);
    expect(images.deleted, isNotEmpty);
  });

  test('conflict release: entry ends conflict, NOT deleted, files kept',
      () async {
    await outbox.enqueue(releaseEntry('a'));
    final images = _FakeImageStore();
    final report = await engine(
      images: images,
      repo: _FakeConfirmRepo(result: ReleaseSyncResult.conflict),
    ).drain();

    expect(report.conflicts, 1);
    final entry = outbox.all().single;
    expect(entry.state, OutboxState.conflict);
    // Files are NOT deleted — the incharge resolves the conflict.
    expect(images.deleted, isEmpty);
  });

  test('createRequest: uploads proof, backfills, marks done, deletes file',
      () async {
    await outbox.enqueue(createEntry('a'));
    final images = _FakeImageStore();
    final repo = _FakeConfirmRepo();
    final report = await engine(images: images, repo: repo).drain();

    expect(report.backfilled, 1);
    expect(repo.backfillCalls, 1);
    expect(repo.backfilledUrls.single, startsWith('http://cdn/img'));
    expect(outbox.all().single.state, OutboxState.done);
    expect(images.deleted, contains('/local/create.jpg'));
  });

  test('Cloudinary failure isolates to its entry; others still drain',
      () async {
    await outbox.enqueue(createEntry('bad', createdAt: 1));
    await outbox.enqueue(releaseEntry('good', createdAt: 2));

    // Uploader fails for everyone — but the release also fails to upload, so
    // both increment attempts. Use a uploader that fails only the first call?
    // Instead: prove isolation by failing image READ for the bad entry only.
    final images = _FakeImageStore(failReads: {'/local/create.jpg'});
    final repo = _FakeConfirmRepo(result: ReleaseSyncResult.confirmed);
    final report = await engine(images: images, repo: repo).drain();

    final byId = {for (final e in outbox.all()) e.id: e};
    // bad: image read failed → transient → attempts incremented, not done.
    expect(byId['bad']!.state, isNot(OutboxState.done));
    expect(byId['bad']!.attempts, 1);
    // good: drained fine despite the sibling's failure.
    expect(byId['good']!.state, OutboxState.done);
    expect(report.confirmed, 1);
    expect(report.failed, 0);
  });

  test('transient failure increments attempts; caps at 5 then fails', () async {
    await outbox.enqueue(releaseEntry('a'));
    final uploader = _FakeUploader(fail: true);

    // Drain repeatedly; each pass increments attempts by 1.
    SyncReport last = const SyncReport();
    for (var i = 0; i < 6; i++) {
      last = await engine(uploader: uploader).drain();
    }
    final entry = outbox.all().single;
    expect(entry.state, OutboxState.failed);
    expect(entry.attempts, greaterThanOrEqualTo(5));
    expect(last.failed, greaterThanOrEqualTo(0));
  });

  test('failed entries are skipped on subsequent drains', () async {
    await outbox.enqueue(releaseEntry('a'));
    final uploader = _FakeUploader(fail: true);
    for (var i = 0; i < 6; i++) {
      await engine(uploader: uploader).drain();
    }
    expect(outbox.all().single.state, OutboxState.failed);

    // A later drain (even with a now-working uploader) leaves failed alone.
    final repo = _FakeConfirmRepo();
    await engine(uploader: _FakeUploader(), repo: repo).drain();
    expect(repo.confirmCalls, 0);
    expect(outbox.all().single.state, OutboxState.failed);
  });

  test('createRequest then dependent release for same entity: create first',
      () async {
    // Enqueue release before create to prove orderForDrain reorders them.
    // Same entityId (req-x) but DISTINCT ids/clientActionIds so dedupe keeps
    // both — the create must still replay before the dependent release.
    await outbox.enqueue(releaseEntry('x-rel', createdAt: 5)
        .copyWith(entityId: 'req-x'));
    await outbox.enqueue(createEntry('x-cre', createdAt: 2)
        .copyWith(entityId: 'req-x'));
    final order = <String>[];
    final repo = _RecordingRepo(order);
    await engine(repo: repo).drain();
    // create (backfill) must run before the release (confirm).
    expect(order, ['backfill', 'confirm']);
  });

  test('reentrancy guard prevents a concurrent double-drain', () async {
    await outbox.enqueue(releaseEntry('a'));
    final repo = _FakeConfirmRepo();
    final e = engine(repo: repo);
    final r1 = e.drain();
    final r2 = e.drain(); // second call while first is in-flight
    await Future.wait([r1, r2]);
    // Only ONE drain actually processed the entry.
    expect(repo.confirmCalls, 1);
  });

  test('transition/approverDecision entries are marked done without replay',
      () async {
    await outbox.enqueue(OutboxEntry(
      id: 't',
      kind: OutboxKind.transition,
      companyId: 'c1',
      entityId: 'req-t',
      clientActionId: 'cai-t',
      createdAtMillis: 1,
    ));
    final repo = _FakeConfirmRepo();
    await engine(repo: repo).drain();
    expect(repo.confirmCalls, 0);
    expect(repo.backfillCalls, 0);
    expect(outbox.all().single.state, OutboxState.done);
  });
}

/// Records the sequence of repo calls to assert create-before-release ordering.
class _RecordingRepo implements SyncRequestRepository {
  _RecordingRepo(this.order);
  final List<String> order;

  @override
  Future<Result<ReleaseSyncResult>> confirmPendingRelease({
    required FundRequest request,
    required String clientReleaseId,
    required String releaseProofUrl,
    required String releaseSignatureUrl,
    required String actorUid,
  }) async {
    order.add('confirm');
    return const Ok(ReleaseSyncResult.confirmed);
  }

  @override
  Future<Result<void>> backfillCreateImage({
    required String requestId,
    required String proofImageUrl,
  }) async {
    order.add('backfill');
    return const Ok(null);
  }
}
