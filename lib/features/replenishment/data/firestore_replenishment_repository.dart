import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/money/money.dart';
import '../../companies/domain/fund.dart';
import '../../requests/domain/request_status.dart';
import '../domain/replenishment.dart';
import '../domain/replenishment_status.dart';
import '../domain/replenishment_repository.dart';

class FirestoreReplenishmentRepository implements ReplenishmentRepository {
  final FirebaseFirestore _db;
  FirestoreReplenishmentRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _reps => _db.collection('replenishments');
  CollectionReference<Map<String, dynamic>> get _requests => _db.collection('requests');
  DocumentReference<Map<String, dynamic>> _fundRef(String id) => _db.collection('funds').doc(id);

  @override
  Stream<List<Replenishment>> watchByFund(String fundId) => _reps
      .where('fundId', isEqualTo: fundId)
      .snapshots()
      .map((s) => s.docs.map((d) => Replenishment.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<Replenishment>> watchByCompanyAndStatus(String companyId, String status) => _reps
      .where('companyId', isEqualTo: companyId)
      .where('status', isEqualTo: status)
      .snapshots()
      .map((s) => s.docs.map((d) => Replenishment.fromMap(d.id, d.data())).toList());

  @override
  Future<Result<String>> createDraft({required String fundId, required String createdByUid}) async {
    try {
      // Query released requests for the fund OUTSIDE the transaction (client SDK
      // transactions cannot run queries). The released-unreplenished filter is
      // applied client-side: equality-on-null queries are not supported by the
      // fake_cloud_firestore test double, and once a request is `replenished` it
      // leaves the `released` set anyway, so this is equivalent in production.
      final snap = await _requests
          .where('fundId', isEqualTo: fundId)
          .where('status', isEqualTo: RequestStatus.released.name)
          .get();
      final unreplenished =
          snap.docs.where((d) => d.data()['replenishmentId'] == null).toList();
      if (unreplenished.isEmpty) {
        return const Err(ValidationFailure('No released requests to replenish.'));
      }
      final ids = unreplenished.map((d) => d.id).toList();
      if (ids.length > 450) {
        return const Err(ValidationFailure(
            'Too many requests to replenish at once (max 450). Replenish in smaller batches.'));
      }
      var total = Money.zero;
      for (final d in unreplenished) {
        total += Money.fromCentavos((d.data()['amountCentavos'] ?? 0) as int);
      }
      final newRef = _reps.doc();
      await _db.runTransaction((tx) async {
        final fundSnap = await tx.get(_fundRef(fundId));
        if (!fundSnap.exists) throw StateError('Fund not found.');
        final fund = Fund.fromMap(fundSnap.id, fundSnap.data()!);
        if (fund.status == FundStatus.replenishing) {
          throw StateError('This fund is already being replenished.');
        }
        tx.set(newRef, {
          'companyId': fund.companyId,
          'fundId': fundId,
          'status': ReplenishmentStatus.draft.name,
          'requestIds': ids,
          'totalCentavos': total.centavos,
          'reportNotes': '',
          'createdByUid': createdByUid,
          'submittedByUid': null,
          'approvedByUid': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(_fundRef(fundId), {'status': FundStatus.replenishing.name});
      });
      return Ok(newRef.id);
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('createDraft failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not start a replenishment.'));
    }
  }

  @override
  Future<Result<void>> submit({required Replenishment replenishment, required String actorUid, required String notes}) async {
    if (!replenishment.status.canTransitionTo(ReplenishmentStatus.submitted)) {
      return const Err(ValidationFailure('Only a draft can be submitted.'));
    }
    try {
      await _reps.doc(replenishment.id).update({
        'status': ReplenishmentStatus.submitted.name,
        'reportNotes': notes,
        'submittedByUid': actorUid,
        'submittedAt': FieldValue.serverTimestamp(),
      });
      await _addNotification(
        companyId: replenishment.companyId,
        recipientRoles: const ['superior', 'manager', 'ceo'],
        type: 'replenishmentSubmitted',
        title: 'Replenishment submitted',
        body: 'A replenishment report needs your approval.',
        fundId: replenishment.fundId,
        replenishmentId: replenishment.id,
      );
      return const Ok(null);
    } catch (e, st) {
      developer.log('submit failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not submit the report.'));
    }
  }

  @override
  Future<Result<void>> approve({required Replenishment replenishment, required String actorUid}) async {
    if (!replenishment.status.canTransitionTo(ReplenishmentStatus.approved)) {
      return const Err(ValidationFailure('Only a submitted report can be approved.'));
    }
    try {
      await _db.runTransaction((tx) async {
        final repRef = _reps.doc(replenishment.id);
        final repSnap = await tx.get(repRef);
        if (!repSnap.exists) throw StateError('Replenishment not found.');
        final current = ReplenishmentStatus.fromName(repSnap.data()!['status'] as String?);
        if (!current.canTransitionTo(ReplenishmentStatus.approved)) {
          throw StateError('This report was already decided.');
        }
        final fundSnap = await tx.get(_fundRef(replenishment.fundId));
        if (!fundSnap.exists) throw StateError('Fund not found.');
        final fund = Fund.fromMap(fundSnap.id, fundSnap.data()!);
        // Writes (all reads done above):
        tx.update(_fundRef(replenishment.fundId), {
          'availableBalanceCentavos': fund.originalBudget.centavos,
          'status': FundStatus.active.name,
        });
        for (final rid in replenishment.requestIds) {
          tx.update(_requests.doc(rid), {
            'status': RequestStatus.replenished.name,
            'replenishmentId': replenishment.id,
          });
        }
        tx.update(repRef, {
          'status': ReplenishmentStatus.approved.name,
          'approvedByUid': actorUid,
          'decidedAt': FieldValue.serverTimestamp(),
        });
      });
      await _addNotification(
        companyId: replenishment.companyId,
        recipientRoles: const ['incharge'],
        type: 'replenishmentApproved',
        title: 'Replenishment approved',
        body: 'The fund has been replenished and is ready for requests.',
        fundId: replenishment.fundId,
        replenishmentId: replenishment.id,
      );
      return const Ok(null);
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('approve failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not approve the report.'));
    }
  }

  @override
  Future<Result<void>> reject({required Replenishment replenishment, required String actorUid}) async {
    if (!replenishment.status.canTransitionTo(ReplenishmentStatus.rejected)) {
      return const Err(ValidationFailure('Only a submitted report can be rejected.'));
    }
    try {
      await _db.runTransaction((tx) async {
        final fundSnap = await tx.get(_fundRef(replenishment.fundId));
        if (!fundSnap.exists) throw StateError('Fund not found.');
        final fund = Fund.fromMap(fundSnap.id, fundSnap.data()!);
        tx.update(_fundRef(replenishment.fundId), {'status': _restoredStatus(fund).name});
        tx.update(_reps.doc(replenishment.id), {
          'status': ReplenishmentStatus.rejected.name,
          'approvedByUid': actorUid,
          'decidedAt': FieldValue.serverTimestamp(),
        });
      });
      await _addNotification(
        companyId: replenishment.companyId,
        recipientRoles: const ['incharge'],
        type: 'replenishmentRejected',
        title: 'Replenishment rejected',
        body: 'Your replenishment report was rejected.',
        fundId: replenishment.fundId,
        replenishmentId: replenishment.id,
      );
      return const Ok(null);
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('reject failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not reject the report.'));
    }
  }

  @override
  Future<Result<void>> discardDraft({required Replenishment replenishment}) async {
    if (replenishment.status != ReplenishmentStatus.draft) {
      return const Err(ValidationFailure('Only a draft can be discarded.'));
    }
    try {
      await _db.runTransaction((tx) async {
        final fundSnap = await tx.get(_fundRef(replenishment.fundId));
        if (fundSnap.exists) {
          final fund = Fund.fromMap(fundSnap.id, fundSnap.data()!);
          tx.update(_fundRef(replenishment.fundId),
              {'status': _restoredStatus(fund).name});
        }
        tx.update(_reps.doc(replenishment.id), {'status': ReplenishmentStatus.rejected.name});
      });
      return const Ok(null);
    } catch (e, st) {
      developer.log('discardDraft failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not discard the draft.'));
    }
  }

  /// Recomputes fund status from its CURRENT (unchanged) balance — used when a
  /// replenishment is rejected/discarded. The prior status is not preserved verbatim;
  /// it is derived from balance, which is self-consistent with FundStatus semantics.
  FundStatus _restoredStatus(Fund fund) =>
      fund.isLow ? FundStatus.low : FundStatus.active;

  Future<void> _addNotification({
    required String companyId,
    required List<String> recipientRoles,
    required String type,
    required String title,
    required String body,
    String? fundId,
    String? replenishmentId,
  }) async {
    try {
      await _db.collection('notifications').add({
        'companyId': companyId,
        'recipientRoles': recipientRoles,
        'type': type,
        'title': title,
        'body': body,
        'fundId': fundId,
        'replenishmentId': replenishmentId,
        'readAt': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      developer.log('notification write failed', name: 'replenishment', error: e, stackTrace: st);
    }
  }
}
