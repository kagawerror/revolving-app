import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/money/money.dart';
import '../../companies/domain/fund.dart';
import '../../messaging/domain/push_sender.dart';
import '../../sync/domain/release_intent.dart';
import '../../sync/domain/release_reconcile.dart';
import '../../sync/domain/release_sync_result.dart';
import '../domain/fund_request.dart';
import '../domain/release_math.dart';
import '../domain/release_preconditions.dart';
import '../domain/request_repository.dart';
import '../domain/request_status.dart';

/// Pure decision used inside the release transaction — unit-testable without Firestore.
class ReleaseOutcome {
  final Money newBalance;
  final bool fundIsLow;
  const ReleaseOutcome(this.newBalance, this.fundIsLow);
}

ReleaseOutcome computeRelease(Fund fund, Money amount) {
  if (fund.status == FundStatus.replenishing) {
    throw StateError('Fund is being replenished; releases are paused.');
  }
  if (!fund.canRelease(amount)) {
    throw StateError('Insufficient fund balance for release.');
  }
  // Arithmetic lives in release_math so the offline reconcile path stays in sync.
  final newBalance = balanceAfterRelease(fund, amount);
  return ReleaseOutcome(newBalance, isLowAfter(fund, newBalance));
}

class FirestoreRequestRepository implements RequestRepository {
  final FirebaseFirestore _db;
  final PushSender _push;
  FirestoreRequestRepository(this._db, [PushSender? push])
      : _push = push ?? const NoopPushSender();

  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('requests');
  DocumentReference<Map<String, dynamic>> _fundRef(String id) =>
      _db.collection('funds').doc(id);

  @override
  Stream<List<FundRequest>> watchByFund(String companyId, String fundId) =>
      _requests
          // companyId is required, not just fundId: the read rule is
          // sameCompany(resource.data.companyId) and Firestore rejects any list
          // query it can't prove is company-scoped. Equality-only on both
          // fields → served by single-field indexes, no composite index needed.
          .where('companyId', isEqualTo: companyId)
          .where('fundId', isEqualTo: fundId)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<FundRequest>> watchByStatus(String companyId, RequestStatus status) =>
      _requests
          .where('companyId', isEqualTo: companyId)
          .where('status', isEqualTo: status.name)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<FundRequest>> watchAcknowledgedWorklist(String companyId) => _requests
      // Release-first: the incharge worklist is requests still awaiting release.
      .where('companyId', isEqualTo: companyId)
      .where('status', isEqualTo: RequestStatus.created.name)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<FundRequest>> watchApproverActedRecent(String companyId, int limit) =>
      _requests
          .where('companyId', isEqualTo: companyId)
          .where('status', whereIn: [
            RequestStatus.acknowledged.name,
            RequestStatus.disputed.name,
            RequestStatus.released.name,
          ])
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<FundRequest>> watchRecentByCompany(String companyId, int limit) => _requests
      .where('companyId', isEqualTo: companyId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<FundRequest>> watchByStatusAll(RequestStatus status) => _requests
      .where('status', isEqualTo: status.name)
      .snapshots()
      .map((s) => s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<FundRequest>> watchRecentAll(int limit) => _requests
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<FundRequest>> watchReleasedByCompany(String companyId) => _requests
      .where('companyId', isEqualTo: companyId)
      .where('status', isEqualTo: RequestStatus.released.name)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<FundRequest>> watchConflicts(String companyId) => _requests
      .where('companyId', isEqualTo: companyId)
      .where('status', isEqualTo: RequestStatus.conflict.name)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<FundRequest>> watchPostReleaseReview(String companyId) => _requests
      .where('companyId', isEqualTo: companyId)
      .where('status', isEqualTo: RequestStatus.released.name)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<FundRequest>> watchDisputed(String companyId) => _requests
      .where('companyId', isEqualTo: companyId)
      .where('status', isEqualTo: RequestStatus.disputed.name)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<FundRequest>> watchReleasedAll(int limit) => _requests
      .where('status', isEqualTo: RequestStatus.released.name)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Future<Result<FundRequest>> getById(String id) async {
    try {
      final snap = await _requests.doc(id).get();
      if (!snap.exists) {
        return const Err(NotFoundFailure('This request is no longer available.'));
      }
      return Ok(FundRequest.fromMap(snap.id, snap.data()!));
    } catch (e, st) {
      developer.log('getById failed', name: 'requests', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not load the request.'));
    }
  }

  @override
  Future<Result<String>> create(FundRequest request) async {
    // Online create requires a proof image up front. An offline create defers
    // the image (carries a pendingImageRef instead) and backfills the URL on
    // sync, so it is exempt from this guard.
    if (request.status == RequestStatus.created &&
        !request.hasProof &&
        request.pendingImageRef == null) {
      return const Err(ValidationFailure('A proof image is required.'));
    }
    // OFFLINE create (deferred image → pendingImageRef): mint a client-side doc
    // id and write WITHOUT awaiting. With offline persistence the write Future
    // does not complete until the server acks it, so awaiting `.add()` here
    // hangs forever while offline — the submit spinner never clears. The local
    // cache mutation applies synchronously, which is all the offline path needs;
    // the writes flush on reconnect. Mirrors `captureLocalRelease`.
    if (request.pendingImageRef != null) {
      try {
        final ref = _requests.doc(); // client-generated id, available now
        unawaited(ref.set(request.toCreateMap()));
        unawaited(_appendHistory(ref.id, 'created', request.createdByUid,
            to: request.status));
        return Ok(ref.id);
      } catch (e, st) {
        developer.log('offline create failed',
            name: 'requests', error: e, stackTrace: st);
        return const Err(UnexpectedFailure('Could not save the request.'));
      }
    }
    // ONLINE create: await so a server-side rejection (e.g. rules) surfaces as
    // an Err the user sees, instead of a silent optimistic success.
    try {
      final ref = await _requests.add(request.toCreateMap());
      await _appendHistory(ref.id, 'created', request.createdByUid,
          to: request.status);
      return Ok(ref.id);
    } catch (e, st) {
      developer.log('create failed', name: 'requests', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not create the request.'));
    }
  }

  @override
  Future<Result<void>> release({
    required FundRequest request,
    required String actorUid,
    required String releaseProofUrl,
    required String releaseSignatureUrl,
    required String clientReleaseId,
  }) {
    return _runRelease(
      request: request,
      actorUid: actorUid,
      releaseProofUrl: releaseProofUrl,
      releaseSignatureUrl: releaseSignatureUrl,
      clientReleaseId: clientReleaseId,
    );
  }

  @override
  Future<Result<void>> captureLocalRelease({
    required FundRequest request,
    required String clientReleaseId,
    required String actorUid,
  }) async {
    // Mirror the online guard: only a 'created' (or conflict) request may flip
    // to 'released'. Validate the transition before writing.
    if (!request.status.canTransitionTo(RequestStatus.released)) {
      return Err(ValidationFailure(
          'Request cannot be released from ${request.status.name}.'));
    }
    try {
      final reqRef = _requests.doc(request.id);
      // PLAIN update (no transaction): a runTransaction needs a server
      // round-trip and would block/fail while offline. This write queues in the
      // Firestore cache and surfaces immediately via cache-backed streams. It
      // MUST NOT touch the fund balance — the server release transaction debits
      // the fund exactly once (online release / Phase-5 replay). The optimistic
      // balance provider is the only local reflection of this pending release.
      //
      // NOT awaited: with offline persistence the write Future does not complete
      // until the server confirms, so awaiting would hang while offline. The
      // local cache mutation is applied synchronously, which is all the offline
      // capture needs; the Future resolves later on reconnect.
      unawaited(reqRef.update({
        'status': RequestStatus.released.name,
        'releaseState': 'localPending',
        'clientReleaseId': clientReleaseId,
        'releaseProofUrl': '',
        'releaseSignatureUrl': '',
        'pendingImageRef': clientReleaseId,
      }));
      unawaited(reqRef.collection('history').add({
        'event': 'released',
        'actorUid': actorUid,
        'from': request.status.name,
        'to': RequestStatus.released.name,
        'note': 'Captured offline; pending sync.',
        'clientReleaseId': clientReleaseId,
        'releaseState': 'localPending',
        'at': FieldValue.serverTimestamp(),
      }));
      return const Ok(null);
    } catch (e, st) {
      developer.log('captureLocalRelease failed',
          name: 'requests', error: e, stackTrace: st);
      return const Err(
          UnexpectedFailure('Could not record the release on your device.'));
    }
  }

  @override
  Future<Result<ReleaseSyncResult>> confirmPendingRelease({
    required FundRequest request,
    required String clientReleaseId,
    required String releaseProofUrl,
    required String releaseSignatureUrl,
    required String actorUid,
  }) async {
    // Proof + signature must already be uploaded by the engine. Reject BEFORE
    // opening any transaction so a missing capture never debits the fund.
    final precondition = ensureReleaseSignature(
      releaseProofUrl: releaseProofUrl,
      releaseSignatureUrl: releaseSignatureUrl,
    );
    if (precondition != null) {
      return Err(precondition);
    }
    ReleaseSyncResult? result;
    _LowBalanceAlert? alert;
    _RequestAlert? requestAlert;
    try {
      await _db.runTransaction((tx) async {
        // Reset per-attempt so a transaction RETRY never re-fires a stale push.
        result = null;
        alert = null;
        requestAlert = null;
        // ALL reads before ANY writes (Firestore transaction rule).
        final reqRef = _requests.doc(request.id);
        final reqSnap = await tx.get(reqRef);
        if (!reqSnap.exists) {
          throw _NotFound('Request not found.');
        }
        final data = reqSnap.data()!;
        final releaseState = data['releaseState'] as String?;

        // IDEMPOTENT: a prior replay already confirmed this release. No second
        // debit. Backfill the URLs / clear pendingImageRef only if still empty.
        if (releaseState == 'serverConfirmed') {
          final currentProof = (data['releaseProofUrl'] ?? '') as String;
          final currentSig = (data['releaseSignatureUrl'] ?? '') as String;
          final backfill = <String, dynamic>{};
          if (currentProof.isEmpty) backfill['releaseProofUrl'] = releaseProofUrl;
          if (currentSig.isEmpty) {
            backfill['releaseSignatureUrl'] = releaseSignatureUrl;
          }
          if ((data['pendingImageRef'] as String?)?.isNotEmpty ?? false) {
            backfill['pendingImageRef'] = '';
          }
          if (backfill.isNotEmpty) tx.update(reqRef, backfill);
          result = ReleaseSyncResult.alreadyConfirmed;
          return;
        }

        // IDEMPOTENT: already resolved to conflict — leave it for the incharge.
        final currentStatus = RequestStatus.fromName(data['status'] as String?);
        if (releaseState == 'conflict' ||
            currentStatus == RequestStatus.conflict) {
          result = ReleaseSyncResult.conflict;
          return;
        }

        // Re-read the CURRENT server fund and reconcile against it.
        final fundSnap = await tx.get(_fundRef(request.fundId));
        if (!fundSnap.exists) {
          throw _NotFound('Fund not found.');
        }
        final fund = Fund.fromMap(fundSnap.id, fundSnap.data()!);
        final intent = ReleaseIntent(
          requestId: request.id,
          fundId: request.fundId,
          companyId: request.companyId,
          amount: request.amount,
          clientReleaseId: clientReleaseId,
        );
        final decision =
            reconcileRelease(fund, intent, alreadyApplied: false);

        switch (decision) {
          case ReconcileApplied(:final newBalance, :final fundIsLow):
            tx.update(_fundRef(request.fundId), {
              'availableBalanceCentavos': newBalance.centavos,
              'status': fundIsLow ? FundStatus.low.name : fund.status.name,
            });
            tx.update(reqRef, {
              'status': RequestStatus.released.name,
              'releasedAt': FieldValue.serverTimestamp(),
              'releaseProofUrl': releaseProofUrl,
              'releaseSignatureUrl': releaseSignatureUrl,
              'clientReleaseId': clientReleaseId,
              'releaseState': 'serverConfirmed',
              'pendingImageRef': '',
            });
            final historyRef = reqRef.collection('history').doc();
            tx.set(historyRef, {
              'event': 'releaseConfirmed',
              'actorUid': actorUid,
              'from': currentStatus.name,
              'to': RequestStatus.released.name,
              'note': 'Offline release confirmed on sync.',
              'clientReleaseId': clientReleaseId,
              'releaseState': 'serverConfirmed',
              'at': FieldValue.serverTimestamp(),
            });
            alert = _stageLowBalanceAlert(tx, fund, fundIsLow);
            // Offline release reaching the server: notify approvers exactly here
            // (applied branch only — NOT on a conflict outcome). The offline
            // capture (captureLocalRelease) stages nothing, and _runRelease is
            // not reused by this path, so an offline release fires exactly one
            // requestReleased notification, at confirm time.
            requestAlert = _stageRequestNotification(
              tx,
              companyId: fund.companyId,
              recipientRoles: const ['superior', 'manager', 'ceo'],
              type: 'requestReleased',
              title: 'New release to review',
              body: 'A cash release needs your review.',
              requestId: request.id,
              requestAmountCentavos: request.amount.centavos,
              requestBeneficiaryName: request.beneficiaryName,
              requestPurpose: request.purpose,
              fundName: fund.name,
            );
            result = ReleaseSyncResult.confirmed;
          case ReconcileConflictInsufficient():
            tx.update(reqRef, {
              'status': RequestStatus.conflict.name,
              'releaseState': 'conflict',
            });
            final historyRef = reqRef.collection('history').doc();
            tx.set(historyRef, {
              'event': 'conflict',
              'actorUid': actorUid,
              'from': currentStatus.name,
              'to': RequestStatus.conflict.name,
              'note': 'Insufficient fund balance on sync; overdraft conflict.',
              'clientReleaseId': clientReleaseId,
              'releaseState': 'conflict',
              'at': FieldValue.serverTimestamp(),
            });
            result = ReleaseSyncResult.conflict;
          case ReconcileAlreadyApplied():
            // Unreachable: we pass alreadyApplied:false and handle the
            // serverConfirmed ledger above. Defensive no-op.
            result = ReleaseSyncResult.alreadyConfirmed;
        }
      });
      _firePush(alert);
      _fireRequestPush(requestAlert);
      return Ok(result!);
    } on _NotFound catch (e) {
      return Err(NotFoundFailure(e.message));
    } catch (e, st) {
      developer.log('confirmPendingRelease failed',
          name: 'requests', error: e, stackTrace: st);
      return const Err(
          UnexpectedFailure('Could not confirm the release. Please retry.'));
    }
  }

  @override
  Future<Result<void>> backfillCreateImage({
    required String requestId,
    required String proofImageUrl,
  }) async {
    if (proofImageUrl.isEmpty) {
      return const Err(ValidationFailure('A proof image URL is required.'));
    }
    try {
      await _db.runTransaction((tx) async {
        final ref = _requests.doc(requestId);
        final snap = await tx.get(ref);
        // TRANSIENT, NOT terminal: the offline `create` write rides Firestore's
        // own offline queue, which flushes on its own schedule — independently
        // of the connectivity probe that fires this drain. So the doc can be
        // absent here simply because the create hasn't reached the server yet
        // (transactions read server state only, never the cache). Surface a
        // retryable NotFound so the engine KEEPS the local proof and retries on a
        // later drain — exactly like confirmPendingRelease. Returning Ok here
        // would retire the outbox entry and delete the only copy of the proof,
        // losing it forever ("No proof photo"). Requests are never deleted, so a
        // genuinely-gone doc cannot happen.
        if (!snap.exists) {
          throw _NotFound('Request not on the server yet.');
        }
        // Idempotent no-op once the create proof is already backfilled: it is
        // WRITE-ONCE, so re-running must retire the entry cleanly rather than
        // re-attempt a write the rule now rejects for a non-empty proofImageUrl.
        final current = (snap.data()?['proofImageUrl'] ?? '') as String;
        if (current.isNotEmpty) return;
        tx.update(ref, {
          'proofImageUrl': proofImageUrl,
          'pendingImageRef': '',
        });
      });
      return const Ok(null);
    } on _NotFound catch (e) {
      // Retryable: the drain bumps attempts and tries again once the create
      // write has flushed (or parks it as failed after the cap for the incharge).
      return Err(NotFoundFailure(e.message));
    } catch (e, st) {
      developer.log('backfillCreateImage failed',
          name: 'requests', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not attach the proof image.'));
    }
  }

  /// Shared release transaction reused by [release] and
  /// [resolveConflict] (to: released) so the money re-validates via
  /// [computeRelease] in exactly one place.
  Future<Result<void>> _runRelease({
    required FundRequest request,
    required String actorUid,
    required String releaseProofUrl,
    required String releaseSignatureUrl,
    required String clientReleaseId,
  }) async {
    // Mandatory proof photo + recipient signature — reject BEFORE opening any
    // transaction so a missing capture never deducts the fund.
    final precondition = ensureReleaseSignature(
      releaseProofUrl: releaseProofUrl,
      releaseSignatureUrl: releaseSignatureUrl,
    );
    if (precondition != null) {
      return Err(precondition);
    }
    if (!request.status.canTransitionTo(RequestStatus.released)) {
      return Err(ValidationFailure(
          'Request cannot be released from ${request.status.name}.'));
    }
    _LowBalanceAlert? alert;
    _RequestAlert? requestAlert;
    try {
      await _db.runTransaction((tx) async {
        // Reset per-attempt so a transaction RETRY never re-fires a stale push.
        alert = null;
        requestAlert = null;
        // ALL reads before ANY writes (Firestore transaction rule). Re-read the
        // request against current server state so two users tapping RELEASE on
        // the same worklist row can't both deduct the fund.
        final reqRef = _requests.doc(request.id);
        final reqSnap = await tx.get(reqRef);
        if (!reqSnap.exists) {
          throw StateError('Request not found.');
        }
        final currentStatus =
            RequestStatus.fromName(reqSnap.data()!['status'] as String?);
        if (!currentStatus.canTransitionTo(RequestStatus.released)) {
          // e.g. already 'released' by a concurrent tap — do NOT deduct again.
          throw StateError('Request is no longer releasable.');
        }
        final fundSnap = await tx.get(_fundRef(request.fundId));
        if (!fundSnap.exists) {
          throw StateError('Fund not found.');
        }
        final fund = Fund.fromMap(fundSnap.id, fundSnap.data()!);
        final outcome = computeRelease(fund, request.amount);
        tx.update(_fundRef(request.fundId), {
          'availableBalanceCentavos': outcome.newBalance.centavos,
          'status': outcome.fundIsLow ? FundStatus.low.name : fund.status.name,
        });
        tx.update(reqRef, {
          'status': RequestStatus.released.name,
          'releasedAt': FieldValue.serverTimestamp(),
          'releaseProofUrl': releaseProofUrl,
          'releaseSignatureUrl': releaseSignatureUrl,
          'clientReleaseId': clientReleaseId,
          'releaseState': 'serverConfirmed',
        });
        final historyRef = reqRef.collection('history').doc();
        tx.set(historyRef, {
          'event': 'released',
          'actorUid': actorUid,
          'from': currentStatus.name,
          'to': RequestStatus.released.name,
          'note': null,
          'releaseProofUrl': releaseProofUrl,
          'releaseSignatureUrl': releaseSignatureUrl,
          'clientReleaseId': clientReleaseId,
          'at': FieldValue.serverTimestamp(),
        });
        alert = _stageLowBalanceAlert(tx, fund, outcome.fundIsLow);
        // Notify approvers a release now needs their post-hoc review. Staged in
        // the SAME transaction (mirrors low-balance) so it commits atomically
        // with the release. This is the ONLY online-release notify site; the
        // offline path notifies once at confirm time (confirmPendingRelease),
        // so a single release fires exactly one requestReleased notification.
        requestAlert = _stageRequestNotification(
          tx,
          companyId: fund.companyId,
          recipientRoles: const ['superior', 'manager', 'ceo'],
          type: 'requestReleased',
          title: 'New release to review',
          body: 'A cash release needs your review.',
          requestId: request.id,
          requestAmountCentavos: request.amount.centavos,
          requestBeneficiaryName: request.beneficiaryName,
          requestPurpose: request.purpose,
          fundName: fund.name,
        );
      });
      // Best-effort push AFTER the money transaction commits — only when the
      // fund NEWLY flipped to low. Not awaited; failures never affect release.
      _firePush(alert);
      _fireRequestPush(requestAlert);
      return const Ok(null);
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('release failed', name: 'requests', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Release failed. Please retry.'));
    }
  }

  @override
  Future<Result<void>> acknowledgePostRelease({
    required FundRequest request,
    required String actorUid,
    String? actorName,
    String? fundName,
  }) =>
      _plainTransition(
        request: request,
        to: RequestStatus.acknowledged,
        actorUid: actorUid,
        extraUpdate: {
          'approverUid': actorUid,
          'approverDecisionAt': FieldValue.serverTimestamp(),
        },
        failureMessage: 'Could not acknowledge the release.',
        stageNotification: (tx) => _stageRequestNotification(
          tx,
          companyId: request.companyId,
          recipientRoles: const ['incharge'],
          type: 'requestAcknowledged',
          title: 'Release acknowledged',
          body: 'An approver acknowledged a cash release.',
          requestId: request.id,
          requestAmountCentavos: request.amount.centavos,
          requestBeneficiaryName: request.beneficiaryName,
          fundName: fundName,
          actorName: actorName,
        ),
      );

  @override
  Future<Result<void>> dispute({
    required FundRequest request,
    required String actorUid,
    required String reason,
    String? actorName,
    String? fundName,
  }) =>
      _plainTransition(
        request: request,
        to: RequestStatus.disputed,
        actorUid: actorUid,
        note: reason,
        extraUpdate: {
          'disputedReason': reason,
          'disputedByUid': actorUid,
          'disputedAt': FieldValue.serverTimestamp(),
        },
        failureMessage: 'Could not record the dispute.',
        // The dispute reason is PII — it is NEVER passed to the notification
        // (generic body + no reason field). It stays on the detail screen.
        stageNotification: (tx) => _stageRequestNotification(
          tx,
          companyId: request.companyId,
          recipientRoles: const ['incharge'],
          type: 'requestDisputed',
          title: 'Release disputed',
          body: 'A cash release was disputed.',
          requestId: request.id,
          requestAmountCentavos: request.amount.centavos,
          requestBeneficiaryName: request.beneficiaryName,
          fundName: fundName,
          actorName: actorName,
        ),
      );

  @override
  Future<Result<void>> resolveConflict({
    required FundRequest request,
    required RequestStatus to,
    required String actorUid,
    String? fundName,
  }) {
    if (to == RequestStatus.released) {
      // Re-run the full release transaction so the money re-validates against
      // current server state via computeRelease. The captured proof + signature
      // and the original clientReleaseId are reused (the release already
      // happened on-device; we are reconciling it server-side).
      return _runRelease(
        request: request,
        actorUid: actorUid,
        releaseProofUrl: request.releaseProofUrl,
        releaseSignatureUrl: request.releaseSignatureUrl,
        clientReleaseId: request.clientReleaseId ?? '',
      );
    }
    if (to == RequestStatus.rejected) {
      return _plainTransition(
        request: request,
        to: RequestStatus.rejected,
        actorUid: actorUid,
        failureMessage: 'Could not reject the conflicted release.',
        stageNotification: (tx) => _stageRequestNotification(
          tx,
          companyId: request.companyId,
          recipientRoles: const ['incharge'],
          type: 'requestRejected',
          title: 'Request rejected',
          body: 'A request was rejected.',
          requestId: request.id,
          requestAmountCentavos: request.amount.centavos,
          requestBeneficiaryName: request.beneficiaryName,
          // Display-only fund name for the incharge's alert row; resolved by the
          // caller (the conflict sheet already has the fund stream warm). Null is
          // tolerated — the alert row null-guards it.
          fundName: fundName,
        ),
      );
    }
    return Future.value(
      const Err(ValidationFailure('Conflicts may only resolve to released or rejected.')),
    );
  }

  /// Money-free guarded transition: re-reads + re-validates the status inside a
  /// transaction (concurrent-edit guard), writes the new status plus any
  /// [extraUpdate] fields, and appends a history event. Used by post-hoc
  /// approver actions and conflict rejection — never moves money.
  Future<Result<void>> _plainTransition({
    required FundRequest request,
    required RequestStatus to,
    required String actorUid,
    String? note,
    Map<String, dynamic> extraUpdate = const {},
    required String failureMessage,
    _RequestAlert? Function(Transaction tx)? stageNotification,
  }) async {
    if (!request.status.canTransitionTo(to)) {
      return Err(ValidationFailure(
          'Cannot move ${request.status.name} → ${to.name}.'));
    }
    _RequestAlert? alert;
    try {
      await _db.runTransaction((tx) async {
        // Reset per-attempt so a transaction RETRY never re-fires a stale push.
        alert = null;
        final ref = _requests.doc(request.id);
        final snap = await tx.get(ref);
        if (!snap.exists) throw StateError('Request not found.');
        final current = RequestStatus.fromName(snap.data()!['status'] as String?);
        if (!current.canTransitionTo(to)) {
          throw StateError('This request was already updated by someone else.');
        }
        tx.update(ref, {'status': to.name, ...extraUpdate});
        final historyRef = ref.collection('history').doc();
        tx.set(historyRef, {
          'event': to.name,
          'actorUid': actorUid,
          'from': current.name,
          'to': to.name,
          'note': note,
          'at': FieldValue.serverTimestamp(),
        });
        // Stage the caller's notification in the SAME transaction so it commits
        // atomically with the status change. No money here, ever.
        if (stageNotification != null) alert = stageNotification(tx);
      });
      // Best-effort push AFTER commit. Not awaited; never affects the result.
      _fireRequestPush(alert);
      return const Ok(null);
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('plainTransition failed',
          name: 'requests', error: e, stackTrace: st);
      return Err(UnexpectedFailure(failureMessage));
    }
  }

  Future<void> _appendHistory(
    String requestId,
    String event,
    String actorUid, {
    RequestStatus? from,
    RequestStatus? to,
    String? note,
  }) {
    return _requests.doc(requestId).collection('history').add({
      'event': event,
      'actorUid': actorUid,
      'from': from?.name,
      'to': to?.name,
      'note': note,
      'at': FieldValue.serverTimestamp(),
    });
  }

  /// Stages the in-transaction low-balance notification write, returning the
  /// alert to push AFTER commit — or null when no NEW low flip occurred. Shared
  /// by [_runRelease] (online) and [confirmPendingRelease] (offline replay) so
  /// the "alert only when the fund NEWLY flips to low" rule lives in one place.
  _LowBalanceAlert? _stageLowBalanceAlert(
    Transaction tx,
    Fund fund,
    bool fundIsLow,
  ) {
    if (!(fundIsLow && fund.status != FundStatus.low)) return null;
    final title = 'Fund ${fund.name} is low';
    final body =
        'Fund "${fund.name}" has reached its low-balance threshold. Replenish soon.';
    final notifRef = _db.collection('notifications').doc();
    tx.set(notifRef, {
      'companyId': fund.companyId,
      'recipientRoles': const ['incharge'],
      'type': 'lowBalance',
      'title': title,
      'body': body,
      'fundId': fund.id,
      'replenishmentId': null,
      'readAt': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return _LowBalanceAlert(companyId: fund.companyId, title: title, body: body);
  }

  /// Best-effort push AFTER the money transaction commits. Not awaited; a push
  /// failure never affects the committed release.
  void _firePush(_LowBalanceAlert? alert) {
    if (alert == null) return;
    unawaited(_push.notify(
      companyId: alert.companyId,
      recipientRoles: const ['incharge'],
      title: alert.title,
      body: alert.body,
    ));
  }

  /// Stages a request-lifecycle notification doc INSIDE the transaction (mirrors
  /// [_stageLowBalanceAlert]) and returns the alert to push AFTER commit.
  ///
  /// PRIVACY: the [body] is GENERIC — it carries no amount, name, purpose, or
  /// reason. The amount/beneficiary/purpose live in denormalized fields read
  /// only inside the app's own alert list (rule-scoped to the recipient roles);
  /// they are NEVER sent to the push relay. Disputes pass no reason at all.
  _RequestAlert _stageRequestNotification(
    Transaction tx, {
    required String companyId,
    required List<String> recipientRoles,
    required String type,
    required String title,
    required String body,
    required String requestId,
    int? requestAmountCentavos,
    String? requestBeneficiaryName,
    String? requestPurpose,
    String? fundName,
    String? actorName,
  }) {
    final notifRef = _db.collection('notifications').doc();
    tx.set(notifRef, {
      'companyId': companyId,
      'recipientRoles': recipientRoles,
      'type': type,
      'title': title,
      'body': body,
      'fundId': null,
      'replenishmentId': null,
      'requestId': requestId,
      'requestAmountCentavos': requestAmountCentavos,
      'requestBeneficiaryName': requestBeneficiaryName,
      'requestPurpose': requestPurpose,
      'fundName': fundName,
      'actorName': actorName,
      'readAt': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return _RequestAlert(
      companyId: companyId,
      recipientRoles: recipientRoles,
      title: title,
      body: body,
    );
  }

  /// Best-effort push for a staged request alert, AFTER the transaction commits.
  /// Not awaited; a push failure never affects the committed write. The push
  /// body is the same generic, PII-free text written to the notification doc.
  void _fireRequestPush(_RequestAlert? alert) {
    if (alert == null) return;
    unawaited(_push.notify(
      companyId: alert.companyId,
      recipientRoles: alert.recipientRoles,
      title: alert.title,
      body: alert.body,
    ));
  }
}

/// A staged low-balance alert to push after the transaction commits.
class _LowBalanceAlert {
  final String companyId;
  final String title;
  final String body;
  const _LowBalanceAlert({
    required this.companyId,
    required this.title,
    required this.body,
  });
}

/// A staged request-lifecycle alert to push after the transaction commits.
/// Carries the recipient roles (unlike [_LowBalanceAlert], which is always
/// incharge-only) since request alerts target approvers OR the incharge.
class _RequestAlert {
  final String companyId;
  final List<String> recipientRoles;
  final String title;
  final String body;
  const _RequestAlert({
    required this.companyId,
    required this.recipientRoles,
    required this.title,
    required this.body,
  });
}

/// Internal sentinel: a missing doc inside a transaction maps to NotFoundFailure
/// (distinct from StateError, which maps to ValidationFailure).
class _NotFound implements Exception {
  final String message;
  const _NotFound(this.message);
}
