import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../../../core/error/result.dart';
import '../../requests/domain/fund_request.dart';
import '../../requests/domain/request_status.dart';
import '../domain/outbox_entry.dart';
import '../domain/outbox_ordering.dart';
import '../domain/release_payload.dart';
import '../domain/release_sync_result.dart';
import 'outbox_store.dart';

/// Maximum drain attempts before an entry is parked as [OutboxState.failed].
/// A transient (network/Cloudinary) failure bumps `attempts`; once it crosses
/// this cap the engine stops retrying so a permanently-broken entry never loops
/// forever. The incharge can inspect failed entries (Phase 6 UI).
const int kMaxDrainAttempts = 5;

/// Counts-only summary of a drain pass. NO PII / amounts / paths — safe to log.
class SyncReport {
  final int confirmed;
  final int conflicts;
  final int backfilled;
  final int failed;
  const SyncReport({
    this.confirmed = 0,
    this.conflicts = 0,
    this.backfilled = 0,
    this.failed = 0,
  });

  SyncReport _add({
    int confirmed = 0,
    int conflicts = 0,
    int backfilled = 0,
    int failed = 0,
  }) =>
      SyncReport(
        confirmed: this.confirmed + confirmed,
        conflicts: this.conflicts + conflicts,
        backfilled: this.backfilled + backfilled,
        failed: this.failed + failed,
      );

  @override
  String toString() =>
      'SyncReport(confirmed: $confirmed, conflicts: $conflicts, '
      'backfilled: $backfilled, failed: $failed)';
}

/// Narrow seam over the local image store the engine needs. Implemented by an
/// adapter over `LocalImageStore` in `sync_providers.dart`.
abstract interface class SyncImageStore {
  Future<Result<List<int>>> read(String path);
  Future<void> deleteQuietly(String path);
}

/// Narrow seam over the image uploader. Proof = JPEG, signature = PNG (its own
/// folder/preset). Implemented by an adapter over `CloudinaryUploader`.
abstract interface class SyncUploader {
  Future<Result<String>> uploadProof(Uint8List bytes);
  Future<Result<String>> uploadSignature(Uint8List bytes);
}

/// Narrow seam over the request repository: just the two replay entry points.
/// `RequestRepository` satisfies this directly.
abstract interface class SyncRequestRepository {
  Future<Result<ReleaseSyncResult>> confirmPendingRelease({
    required FundRequest request,
    required String clientReleaseId,
    required String releaseProofUrl,
    required String releaseSignatureUrl,
    required String actorUid,
  });
  Future<Result<void>> backfillCreateImage({
    required String requestId,
    required String proofImageUrl,
  });
}

/// Drains the offline outbox on reconnect:
///  - uploads pending images to Cloudinary,
///  - backfills `createRequest` proof URLs,
///  - REPLAYS captured offline releases through the server-side confirm
///    transaction (debits the fund EXACTLY ONCE, idempotent), flagging
///    overdraft conflicts.
///
/// MONEY SAFETY: the engine never touches the fund. The single debit happens
/// server-side inside `confirmPendingRelease`'s transaction. The engine only
/// orchestrates uploads + invokes the repo and records outbox state.
///
/// Reentrant-safe: a `_draining` lock makes a connectivity blip + app-resume
/// firing together a single drain, not a double-drain.
class SyncEngine {
  SyncEngine({
    required OutboxStore outbox,
    required SyncImageStore images,
    required SyncUploader uploader,
    required SyncRequestRepository requests,
    required String Function() actorUid,
  })  : _outbox = outbox,
        _images = images,
        _uploader = uploader,
        _requests = requests,
        _actorUid = actorUid;

  // ignore_for_file: prefer_initializing_formals

  final OutboxStore _outbox;
  final SyncImageStore _images;
  final SyncUploader _uploader;
  final SyncRequestRepository _requests;
  final String Function() _actorUid;

  bool _draining = false;

  /// Processes the whole outbox once. Each entry is isolated (a per-entry
  /// failure never aborts the drain). Returns a counts-only [SyncReport].
  /// Concurrent calls while a drain is in flight no-op (return an empty report).
  /// Re-arms every parked [OutboxState.failed] entry (resets it to
  /// [OutboxState.pending] with a cleared attempt count) and then drains. Use
  /// for an EXPLICIT user-initiated "Sync now": the automatic backoff parks an
  /// entry as `failed` after [kMaxDrainAttempts] and `drain()` then skips it
  /// forever, so a manual retry needs to un-park it first. Deliberately leaves
  /// [OutboxState.conflict] entries untouched — an overdraft conflict is
  /// resolved through the conflict worklist, not a blind replay.
  ///
  /// Re-arming while offline is fine and useful: the entries become `pending`
  /// again, so the next reconnect drain (or this one, once reachable) retries
  /// them. The drain itself owns the reentrancy guard.
  Future<SyncReport> retryFailedAndDrain() async {
    for (final entry in _outbox.all()) {
      if (entry.state == OutboxState.failed) {
        await _outbox.update(
            entry.copyWith(state: OutboxState.pending, attempts: 0));
      }
    }
    return drain();
  }

  Future<SyncReport> drain() async {
    if (_draining) return const SyncReport();
    _draining = true;
    try {
      final ordered = orderForDrain(_outbox.all());
      var report = const SyncReport();
      for (final entry in ordered) {
        // Skip terminal states: done (finished) and failed (parked after cap)
        // and conflict (the incharge resolves it; not auto-retried).
        if (entry.state == OutboxState.done ||
            entry.state == OutboxState.failed ||
            entry.state == OutboxState.conflict) {
          continue;
        }
        try {
          report = await _processEntry(entry, report);
        } catch (e) {
          // Defensive: an unforeseen throw isolates to this entry. Treat as a
          // transient bump (no PII — generic log only).
          developer.log('Sync drain: entry failed unexpectedly.',
              name: 'SyncEngine');
          report = await _bumpAttempts(entry, report);
        }
      }
      return report;
    } finally {
      _draining = false;
    }
  }

  Future<SyncReport> _processEntry(OutboxEntry entry, SyncReport report) async {
    switch (entry.kind) {
      case OutboxKind.release:
        return _processRelease(entry, report);
      case OutboxKind.createRequest:
        return _processCreate(entry, report);
      case OutboxKind.transition:
      case OutboxKind.approverDecision:
        // These ride Firestore's own offline write queue (a plain queued
        // update replays automatically on reconnect), so the engine does not
        // replay them — just retire the bookkeeping entry.
        await _outbox.markDone(entry.id);
        return report;
    }
  }

  Future<SyncReport> _processRelease(
      OutboxEntry entry, SyncReport report) async {
    final intent = ReleasePayload.decode(entry.payload);
    if (intent == null) {
      // Malformed payload can never succeed — park it as failed (no retry).
      await _outbox.update(entry.copyWith(state: OutboxState.failed));
      return report._add(failed: 1);
    }

    await _outbox.update(entry.copyWith(state: OutboxState.uploading));

    // Upload proof + signature. A missing local file or upload error is
    // transient — bump attempts and retry on a later drain.
    final proofUrl = await _uploadImage(
        intent.localProofPath, _uploader.uploadProof);
    if (proofUrl == null) return _bumpAttempts(entry, report);
    final sigUrl = await _uploadImage(
        intent.localSignaturePath, _uploader.uploadSignature);
    if (sigUrl == null) return _bumpAttempts(entry, report);

    await _outbox.update(entry.copyWith(state: OutboxState.replaying));

    final res = await _requests.confirmPendingRelease(
      // confirmPendingRelease re-reads the request doc inside its transaction;
      // it only consumes id/fundId/companyId/amount from this object, all of
      // which the intent carries. Status here is the released optimistic state.
      request: FundRequest(
        id: intent.requestId,
        companyId: intent.companyId,
        fundId: intent.fundId,
        createdByUid: '',
        beneficiaryName: '',
        amount: intent.amount,
        purpose: '',
        proofImageUrl: '',
        status: RequestStatus.released,
        clientReleaseId: intent.clientReleaseId,
        releaseState: 'localPending',
      ),
      clientReleaseId: intent.clientReleaseId,
      releaseProofUrl: proofUrl,
      releaseSignatureUrl: sigUrl,
      actorUid: _actorUid(),
    );

    return res.when(
      ok: (result) async {
        switch (result) {
          case ReleaseSyncResult.confirmed:
          case ReleaseSyncResult.alreadyConfirmed:
            await _outbox.markDone(entry.id);
            await _deleteLocals(intent.localProofPath, intent.localSignaturePath);
            return report._add(confirmed: 1);
          case ReleaseSyncResult.conflict:
            // Terminal-for-engine: leave the entry + local files for the
            // incharge to resolve (Phase 6). Do NOT auto-retry.
            await _outbox.update(entry.copyWith(state: OutboxState.conflict));
            return report._add(conflicts: 1);
        }
      },
      // Repo-level failure (e.g. transient Firestore error) → retry later.
      err: (_) async => _bumpAttempts(entry, report),
    );
  }

  Future<SyncReport> _processCreate(
      OutboxEntry entry, SyncReport report) async {
    final path =
        entry.localImagePaths.isNotEmpty ? entry.localImagePaths.first : null;
    if (path == null) {
      // No image to backfill — nothing for the engine to do; retire it.
      await _outbox.markDone(entry.id);
      return report;
    }

    await _outbox.update(entry.copyWith(state: OutboxState.uploading));
    final url = await _uploadImage(path, _uploader.uploadProof);
    if (url == null) return _bumpAttempts(entry, report);

    await _outbox.update(entry.copyWith(state: OutboxState.replaying));
    final res = await _requests.backfillCreateImage(
      requestId: entry.entityId,
      proofImageUrl: url,
    );
    return res.when(
      ok: (_) async {
        await _outbox.markDone(entry.id);
        await _images.deleteQuietly(path);
        return report._add(backfilled: 1);
      },
      err: (_) async => _bumpAttempts(entry, report),
    );
  }

  /// Reads [path] and uploads via [upload]. Returns the URL, or null on any
  /// transient failure (missing file / upload error). Null path → null (skip).
  Future<String?> _uploadImage(
    String? path,
    Future<Result<String>> Function(Uint8List bytes) upload,
  ) async {
    if (path == null) return null;
    final read = await _images.read(path);
    final bytes = read.valueOrNull;
    if (bytes == null) return null;
    final res = await upload(Uint8List.fromList(bytes));
    return res.valueOrNull;
  }

  /// Increments attempts; parks as [OutboxState.failed] once the cap is hit so
  /// a broken entry stops retrying (surfaced via the outbox stream).
  Future<SyncReport> _bumpAttempts(OutboxEntry entry, SyncReport report) async {
    final attempts = entry.attempts + 1;
    final state =
        attempts >= kMaxDrainAttempts ? OutboxState.failed : OutboxState.pending;
    await _outbox.update(entry.copyWith(attempts: attempts, state: state));
    return state == OutboxState.failed ? report._add(failed: 1) : report;
  }

  Future<void> _deleteLocals(String? proofPath, String? sigPath) async {
    if (proofPath != null) await _images.deleteQuietly(proofPath);
    if (sigPath != null) await _images.deleteQuietly(sigPath);
  }
}
