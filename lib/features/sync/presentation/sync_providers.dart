import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/error/result.dart';
import '../../../services/cloudinary/cloudinary_uploader.dart';
import '../../../services/firebase/firebase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_providers.dart';
import '../../companies/domain/fund.dart';
import '../../config/presentation/config_providers.dart';
import '../../../core/money/money.dart';
import '../../requests/domain/fund_request.dart';
import '../../requests/domain/request_repository.dart';
import '../../requests/presentation/request_providers.dart';
import '../domain/release_sync_result.dart';
import '../data/local_image_store.dart';
import '../data/outbox_store.dart';
import '../data/sync_engine.dart';
import '../domain/optimistic_balance.dart';
import '../domain/outbox_entry.dart';
import '../domain/release_intent.dart';
import '../domain/release_payload.dart';

/// SharedPreferences instance, resolved eagerly in `main()` and injected via an
/// override on the ProviderScope. It is declared as a throwing Provider so any
/// consumer reached before the bootstrap override fails loudly in dev rather
/// than silently using a wrong store.
///
/// BOOTSTRAP CONTRACT (see main.dart):
/// ```dart
/// final prefs = await SharedPreferences.getInstance();
/// runApp(ProviderScope(
///   overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
///   child: const RevApp(),
/// ));
/// ```
/// Keeping it synchronous lets `outboxStoreProvider` (and its consumers) stay
/// synchronous instead of forcing every reader through an AsyncValue.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main() bootstrap.',
  ),
);

/// The app-global offline mutation queue. KeepAlive (not autoDispose): the queue
/// outlives any single screen and must persist for the whole session.
final outboxStoreProvider = Provider<OutboxStore>(
  (ref) => OutboxStore(ref.watch(sharedPreferencesProvider)),
);

/// Local proof/signature image store, rooted at the app documents directory.
final localImageStoreProvider = Provider<LocalImageStore>(
  (ref) => LocalImageStore(baseDir: getApplicationDocumentsDirectory),
);

/// Live view of the outbox queue. KeepAlive — app-global, like the store.
final outboxProvider = StreamProvider<List<OutboxEntry>>(
  (ref) => ref.watch(outboxStoreProvider).watch(),
);

/// Whether Firestore is server-reachable (vs serving purely from cache).
///
/// Derived from the caller's own `users/{uid}` doc snapshots with
/// `includeMetadataChanges: true`: a snapshot that is NOT from cache means the
/// server answered, so we are online. The user doc is always readable by its
/// owner and company-scoped, making it the safe probe target. Emits `false`
/// while signed out (no doc to probe).
final connectivityProvider = StreamProvider<bool>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) {
    return Stream<bool>.value(false);
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('users')
      .doc(user.uid)
      .snapshots(includeMetadataChanges: true)
      .map((snap) => !snap.metadata.isFromCache);
});

/// Pending local releases for [fundId], decoded from the outbox. Filters to
/// release-kind entries that have not yet completed (done entries no longer
/// affect the optimistic balance) and whose payload targets this fund.
final pendingReleaseIntentsProvider =
    Provider.family<List<ReleaseIntent>, String>((ref, fundId) {
  final entries = ref.watch(outboxProvider).valueOrNull ?? const [];
  final result = <ReleaseIntent>[];
  for (final e in entries) {
    if (e.kind != OutboxKind.release) continue;
    if (e.state == OutboxState.done) continue;
    final intent = ReleasePayload.decode(e.payload);
    if (intent != null && intent.fundId == fundId) {
      result.add(intent);
    }
  }
  return result;
});

/// Optimistic display balance for [fundId]: the server fund balance minus the
/// sum of pending local releases. May be negative (over-commitment) — see
/// [optimisticBalance]. Falls back to a zero balance when the fund has not
/// loaded yet or is absent, so the UI shows server-or-zero rather than crashing;
/// the authoritative value is always the server's.
final optimisticFundBalanceProvider =
    Provider.family<OptimisticBalance, String>((ref, fundId) {
  final serverBalance =
      ref.watch(fundByIdProvider(fundId)).valueOrNull?.availableBalance ??
          Money.zero;
  final pending = ref.watch(pendingReleaseIntentsProvider(fundId));
  return optimisticBalance(serverBalance, pending);
});

/// Single-fund stream by id (reuses the existing FundRepository.watchById). A
/// thin provider so optimistic balance can watch one fund reactively without
/// changing the companies feature's provider surface.
final fundByIdProvider = StreamProvider.family<Fund?, String>(
  (ref, fundId) => ref.watch(fundRepositoryProvider).watchById(fundId),
);

/// Adapter wiring [RequestRepository] to the engine's narrow
/// [SyncRequestRepository] seam (Dart interfaces aren't structural, so the
/// concrete repo can't satisfy the seam by shape alone).
class _RequestRepoAdapter implements SyncRequestRepository {
  _RequestRepoAdapter(this._repo);
  final RequestRepository _repo;
  @override
  Future<Result<ReleaseSyncResult>> confirmPendingRelease({
    required FundRequest request,
    required String clientReleaseId,
    required String releaseProofUrl,
    required String releaseSignatureUrl,
    required String actorUid,
  }) =>
      _repo.confirmPendingRelease(
        request: request,
        clientReleaseId: clientReleaseId,
        releaseProofUrl: releaseProofUrl,
        releaseSignatureUrl: releaseSignatureUrl,
        actorUid: actorUid,
      );
  @override
  Future<Result<void>> backfillCreateImage({
    required String requestId,
    required String proofImageUrl,
  }) =>
      _repo.backfillCreateImage(
        requestId: requestId,
        proofImageUrl: proofImageUrl,
      );
}

/// Adapter wiring [LocalImageStore] to the engine's narrow [SyncImageStore].
class _ImageStoreAdapter implements SyncImageStore {
  _ImageStoreAdapter(this._store);
  final LocalImageStore _store;
  @override
  Future<Result<List<int>>> read(String path) => _store.read(path);
  @override
  Future<void> deleteQuietly(String path) => _store.deleteQuietly(path);
}

/// Adapter wiring [CloudinaryUploader] to the engine's narrow [SyncUploader].
/// Proof = JPEG (default folder/preset); signature = PNG in its own
/// folder/preset (mirrors signatureUploadProvider's direct-upload path).
class _UploaderAdapter implements SyncUploader {
  _UploaderAdapter(this._uploader, this._signatureFolder, this._signaturePreset);
  final CloudinaryUploader _uploader;
  final String _signatureFolder;
  final String _signaturePreset;
  @override
  Future<Result<String>> uploadProof(Uint8List bytes) =>
      _uploader.uploadJpeg(bytes);
  @override
  Future<Result<String>> uploadSignature(Uint8List bytes) => _uploader.uploadPng(
        bytes,
        folder: _signatureFolder,
        preset: _signaturePreset,
      );
}

/// The offline sync engine. Drains the outbox, uploads images, backfills create
/// proofs, and replays captured releases through the server-side confirm
/// transaction. KeepAlive — app-global like the outbox.
///
/// `RequestRepository` already implements the engine's `SyncRequestRepository`
/// seam (confirmPendingRelease + backfillCreateImage), so it is passed directly.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final cfg = ref.watch(effectiveCloudinaryConfigProvider);
  return SyncEngine(
    outbox: ref.watch(outboxStoreProvider),
    images: _ImageStoreAdapter(ref.watch(localImageStoreProvider)),
    uploader: _UploaderAdapter(
      ref.watch(cloudinaryUploaderProvider),
      cfg.signatureFolder,
      cfg.signatureEffectivePreset,
    ),
    requests: _RequestRepoAdapter(ref.watch(requestRepositoryProvider)),
    // The signed-in incharge is the release actor for history attribution.
    actorUid: () => ref.read(currentUserProvider).valueOrNull?.uid ?? '',
  );
});

/// Fire-and-forget drain trigger wired ONCE at the app root (see
/// `SyncTrigger`). Watches [connectivityProvider] and drains on the EDGE from
/// offline → online (false → true), not on every emission, so a steady online
/// session never loops. Phase 6 adds a manual button via
/// `ref.read(syncEngineProvider).drain()`; app-resume can call the same.
///
/// Call from a ConsumerWidget's build (see RevApp wiring); registers a
/// `ref.listen` on connectivity that survives for the widget's lifetime.
void wireSyncOnReconnect(WidgetRef ref) {
  ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
    final was = prev?.valueOrNull ?? false;
    final now = next.valueOrNull ?? false;
    if (!was && now) {
      // Edge offline → online: drain once. Engine's reentrancy guard makes a
      // racing app-resume drain a no-op rather than a double-drain.
      unawaited(ref.read(syncEngineProvider).drain());
    }
  });
}
