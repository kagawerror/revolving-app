import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/money/money.dart';
import '../../auth/domain/app_user.dart';
import '../domain/budget_adjustment.dart';
import '../domain/fund.dart';
import '../domain/fund_adjustment.dart';
import '../domain/fund_repository.dart';

class FirestoreFundRepository implements FundRepository {
  final FirebaseFirestore _db;
  FirestoreFundRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('funds');

  @override
  Stream<List<Fund>> watchByCompany(String companyId) => _col
      .where('companyId', isEqualTo: companyId)
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map((d) => Fund.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<Fund>> watchAll() => _col
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map((d) => Fund.fromMap(d.id, d.data())).toList());

  @override
  Stream<Fund?> watchById(String fundId) => _col
      .doc(fundId)
      .snapshots()
      .map((d) => d.exists ? Fund.fromMap(d.id, d.data()!) : null);

  @override
  Future<Result<void>> create(Fund fund) async {
    try {
      await _col.add(fund.toCreateMap());
      return const Ok(null);
    } catch (e, st) {
      developer.log('create failed', name: 'funds', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not create the fund.'));
    }
  }

  // CODER: implement the real metadata update (and matching firestore.rules).
  @override
  Future<Result<void>> updateDetails({
    required String fundId,
    required String name,
    required int lowBalanceThresholdPct,
  }) async {
    try {
      await _col.doc(fundId).update({
        'name': name,
        'lowBalanceThresholdPct': lowBalanceThresholdPct,
      });
      return const Ok(null);
    } catch (e, st) {
      developer.log('updateDetails failed',
          name: 'funds', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not update the fund.'));
    }
  }

  // Re-sets the original budget and applies the SAME signed delta to the
  // available balance inside a transaction (re-reads + re-validates against the
  // current server state, mirroring `FirestoreRequestRepository.release`).
  // Writes a `history` audit entry. Money never reaches the logs.
  @override
  Future<Result<void>> adjustBudget({
    required String fundId,
    required Money newBudget,
    required String actorUid,
    required String note,
  }) async {
    try {
      await _db.runTransaction((tx) async {
        final ref = _col.doc(fundId);
        final snap = await tx.get(ref);
        if (!snap.exists) throw StateError('Fund not found.');
        final fund = Fund.fromMap(snap.id, snap.data()!);
        final adj = computeBudgetAdjustment(fund, newBudget);
        tx.update(ref, {
          'originalBudgetCentavos': adj.newBudget.centavos,
          'availableBalanceCentavos': adj.newBalance.centavos,
          'status': adj.newStatus.name,
        });
        final historyRef = ref.collection('history').doc();
        tx.set(historyRef, {
          'event': 'budgetAdjusted',
          'actorUid': actorUid,
          'fromBudgetCentavos': fund.originalBudget.centavos,
          'toBudgetCentavos': adj.newBudget.centavos,
          'deltaCentavos': adj.deltaCentavos,
          'fromBalanceCentavos': fund.availableBalance.centavos,
          'toBalanceCentavos': adj.newBalance.centavos,
          if (note.isNotEmpty) 'note': note,
          'at': FieldValue.serverTimestamp(),
        });
      });
      return const Ok(null);
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('adjustBudget failed',
          name: 'funds', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not adjust the budget.'));
    }
  }

  // Applies a signed delta to the available balance ONLY, inside a transaction
  // that re-reads + re-validates against current server state (mirrors
  // `adjustBudget`). The budget and threshold are never touched; status is
  // recomputed against the unchanged budget. Writes a `history` audit entry.
  // Neither the amounts nor the reason ever reach the logs.
  @override
  Future<Result<void>> adjustBalance({
    required String fundId,
    required int signedDeltaCentavos,
    required String reason,
    required String actorUid,
    required UserRole actorRole,
  }) async {
    try {
      // "Reason required" is a money-mutation invariant, enforced here at the
      // seam (not only in the UI) so no caller can persist a blank-reason audit
      // entry. Mapped to ValidationFailure by the StateError catch below.
      if (reason.trim().isEmpty) throw StateError('A reason is required.');
      await _db.runTransaction((tx) async {
        final ref = _col.doc(fundId);
        final snap = await tx.get(ref);
        if (!snap.exists) throw StateError('Fund not found.');
        final fund = Fund.fromMap(snap.id, snap.data()!);
        final adj = computeFundAdjustment(fund, signedDeltaCentavos);
        tx.update(ref, {
          'availableBalanceCentavos': adj.newBalance.centavos,
          'status': adj.newStatus.name,
          'adjustmentsCentavos': FieldValue.increment(adj.signedDeltaCentavos),
        });
        final historyRef = ref.collection('history').doc();
        tx.set(historyRef, {
          'event': 'balanceAdjusted',
          'actorUid': actorUid,
          'actorRole': actorRole.name,
          'signedDeltaCentavos': adj.signedDeltaCentavos,
          'reason': reason,
          'fromBalanceCentavos': fund.availableBalance.centavos,
          'balanceAfterCentavos': adj.newBalance.centavos,
          'at': FieldValue.serverTimestamp(),
        });
      });
      return const Ok(null);
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('adjustBalance failed',
          name: 'funds', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not adjust the fund.'));
    }
  }
}
