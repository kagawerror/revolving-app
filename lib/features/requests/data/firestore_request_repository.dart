import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/money/money.dart';
import '../../companies/domain/fund.dart';
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
  if (!fund.canRelease(amount)) {
    throw StateError('Insufficient fund balance for release.');
  }
  final newBalance = fund.availableBalance - amount;
  final low = newBalance <= fund.lowBalanceThreshold;
  return ReleaseOutcome(newBalance, low);
}

class FirestoreRequestRepository implements RequestRepository {
  final FirebaseFirestore _db;
  FirestoreRequestRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('requests');
  DocumentReference<Map<String, dynamic>> _fundRef(String id) =>
      _db.collection('funds').doc(id);

  @override
  Stream<List<FundRequest>> watchByFund(String fundId) => _requests
      .where('fundId', isEqualTo: fundId)
      .snapshots()
      .map((s) => s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<FundRequest>> watchByStatus(String companyId, RequestStatus status) =>
      _requests
          .where('companyId', isEqualTo: companyId)
          .where('status', isEqualTo: status.name)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

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
    } catch (_) {
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
      await _requests.doc(request.id).update({
        'status': to.name,
        if (to == RequestStatus.acknowledged) ...{
          'approverUid': actorUid,
          'approverDecisionAt': FieldValue.serverTimestamp(),
        },
      });
      await _appendHistory(request.id, to.name, actorUid,
          from: request.status, to: to, note: note);
      return const Ok(null);
    } catch (_) {
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
    try {
      await _db.runTransaction((tx) async {
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
        tx.update(_requests.doc(request.id), {
          'status': RequestStatus.released.name,
          'releasedAt': FieldValue.serverTimestamp(),
        });
      });
      await _appendHistory(request.id, 'released', actorUid,
          from: request.status, to: RequestStatus.released);
      return const Ok(null);
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (_) {
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
