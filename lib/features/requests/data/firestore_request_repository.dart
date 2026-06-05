import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/money/money.dart';
import '../../companies/domain/fund.dart';
import '../../messaging/domain/push_sender.dart';
import '../domain/fund_request.dart';
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
  final newBalance = fund.availableBalance - amount;
  final low = newBalance <= fund.lowBalanceThreshold;
  return ReleaseOutcome(newBalance, low);
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
      .where('companyId', isEqualTo: companyId)
      .where('status', whereIn: [
        RequestStatus.acknowledged.name,
        RequestStatus.readyForRelease.name,
      ])
      .orderBy('createdAt', descending: true)
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
  Future<Result<String>> create(FundRequest request) async {
    if (request.status == RequestStatus.pendingAck && !request.hasProof) {
      return const Err(ValidationFailure('A proof image is required.'));
    }
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
  Future<Result<void>> transition({
    required FundRequest request,
    required RequestStatus to,
    required String actorUid,
    String? note,
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
        tx.update(ref, {
          'status': to.name,
          if (to == RequestStatus.acknowledged) ...{
            'approverUid': actorUid,
            'approverDecisionAt': FieldValue.serverTimestamp(),
          },
        });
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
      developer.log('transition failed',
          name: 'requests', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not update the request.'));
    }
  }

  @override
  Future<Result<void>> release({
    required FundRequest request,
    required String actorUid,
  }) async {
    if (!request.status.canTransitionTo(RequestStatus.released)) {
      return Err(ValidationFailure(
          'Request must be ready-for-release before releasing.'));
    }
    var newlyLow = false;
    Fund? releasedFund;
    String? lowTitle;
    String? lowBody;
    try {
      await _db.runTransaction((tx) async {
        // ALL reads before ANY writes (Firestore transaction rule). Re-read the
        // request against current server state so two users tapping RELEASE on
        // the same acknowledged worklist row can't both deduct the fund.
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
        releasedFund = fund;
        final outcome = computeRelease(fund, request.amount);
        tx.update(_fundRef(request.fundId), {
          'availableBalanceCentavos': outcome.newBalance.centavos,
          'status': outcome.fundIsLow ? FundStatus.low.name : fund.status.name,
        });
        tx.update(reqRef, {
          'status': RequestStatus.released.name,
          'releasedAt': FieldValue.serverTimestamp(),
        });
        final historyRef = reqRef.collection('history').doc();
        tx.set(historyRef, {
          'event': 'released',
          'actorUid': actorUid,
          'from': currentStatus.name,
          'to': RequestStatus.released.name,
          'note': null,
          'at': FieldValue.serverTimestamp(),
        });
        // Low-balance alert ONLY when the fund NEWLY flips to low (avoids
        // spamming incharge on every release once the fund is already low).
        if (outcome.fundIsLow && fund.status != FundStatus.low) {
          newlyLow = true;
          lowTitle = 'Fund ${fund.name} is low';
          lowBody =
              'Fund "${fund.name}" has reached its low-balance threshold. Replenish soon.';
          final notifRef = _db.collection('notifications').doc();
          tx.set(notifRef, {
            'companyId': fund.companyId,
            'recipientRoles': const ['incharge'],
            'type': 'lowBalance',
            'title': lowTitle,
            'body': lowBody,
            'fundId': fund.id,
            'replenishmentId': null,
            'readAt': null,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });
      // Best-effort push AFTER the money transaction commits — only when the
      // fund NEWLY flipped to low. Not awaited; failures never affect release.
      final fund = releasedFund;
      if (newlyLow && fund != null) {
        unawaited(_push.notify(
          companyId: fund.companyId,
          recipientRoles: const ['incharge'],
          title: lowTitle!,
          body: lowBody!,
        ));
      }
      return const Ok(null);
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('release failed', name: 'requests', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Release failed. Please retry.'));
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
}
