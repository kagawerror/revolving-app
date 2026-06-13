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
    try {
      await _db.runTransaction((tx) async {
        // Reset per-attempt so a transaction RETRY never re-fires a stale push.
        result = null;
        alert = null;
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
      await _requests.doc(requestId).update({
        'proofImageUrl': proofImageUrl,
        'pendingImageRef': '',
      });
      return const Ok(null);
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
    try {
      await _db.runTransaction((tx) async {
        // Reset per-attempt so a transaction RETRY never re-fires a stale push.
        alert = null;
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
      });
      // Best-effort push AFTER the money transaction commits — only when the
      // fund NEWLY flipped to low. Not awaited; failures never affect release.
      _firePush(alert);
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
      );

  @override
  Future<Result<void>> dispute({
    required FundRequest request,
    required String actorUid,
    required String reason,
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
      );

  @override
  Future<Result<void>> resolveConflict({
    required FundRequest request,
    required RequestStatus to,
    required String actorUid,
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
  }) async {
    if (!request.status.canTransitionTo(to)) {
      return Err(ValidationFailure(
          'Cannot move ${request.status.name} → ${to.name}.'));
    }
    try {
      await _db.runTransaction((tx) async {
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
      });
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

/// Internal sentinel: a missing doc inside a transaction maps to NotFoundFailure
/// (distinct from StateError, which maps to ValidationFailure).
class _NotFound implements Exception {
  final String message;
  const _NotFound(this.message);
}
