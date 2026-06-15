import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:developer' as developer;

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/money/money.dart';
import '../../companies/domain/fund.dart';
import '../../messaging/domain/push_sender.dart';
import '../../requests/domain/request_status.dart';
import '../domain/replenishment.dart';
import '../domain/replenishment_fill.dart';
import '../domain/replenishment_status.dart';
import '../domain/replenishment_repository.dart';

class FirestoreReplenishmentRepository implements ReplenishmentRepository {
  final FirebaseFirestore _db;
  final PushSender _push;
  FirestoreReplenishmentRepository(this._db, [PushSender? push])
      : _push = push ?? const NoopPushSender();

  CollectionReference<Map<String, dynamic>> get _reps => _db.collection('replenishments');
  CollectionReference<Map<String, dynamic>> get _requests => _db.collection('requests');
  CollectionReference<Map<String, dynamic>> get _partials =>
      _db.collection('partialReplenishments');
  DocumentReference<Map<String, dynamic>> _fundRef(String id) => _db.collection('funds').doc(id);

  @override
  Stream<List<Replenishment>> watchByFund(String companyId, String fundId) =>
      _reps
          // Company-scoped for the sameCompany read rule; a fundId-only list is
          // rejected with permission-denied. Equality-only on both fields, so
          // no composite index is required.
          .where('companyId', isEqualTo: companyId)
          .where('fundId', isEqualTo: fundId)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => Replenishment.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<Replenishment>> watchByCompanyAndStatus(String companyId, String status) => _reps
      .where('companyId', isEqualTo: companyId)
      .where('status', isEqualTo: status)
      .snapshots()
      .map((s) => s.docs.map((d) => Replenishment.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<Replenishment>> watchByCompanyAndStatusRecent(
          String companyId, String status, int limit) =>
      _reps
          .where('companyId', isEqualTo: companyId)
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => Replenishment.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<Replenishment>> watchByStatusAll(String status) => _reps
      .where('status', isEqualTo: status)
      .snapshots()
      .map((s) => s.docs.map((d) => Replenishment.fromMap(d.id, d.data())).toList());

  @override
  Future<Result<Replenishment>> createDraft({
    required String fundId,
    required List<ReplenishmentItem> items,
    required String createdByUid,
  }) async {
    try {
      if (items.isEmpty) {
        return const Err(ValidationFailure('Select at least one request to replenish.'));
      }
      // Reject duplicate requestIds (a request may appear at most once).
      final ids = items.map((i) => i.requestId).toList();
      if (ids.toSet().length != ids.length) {
        return const Err(ValidationFailure('A request was selected more than once.'));
      }
      if (items.length > 200) {
        return const Err(ValidationFailure(
            'Too many requests to replenish at once (max 200). Replenish in smaller batches.'));
      }
      // Read the fund first to learn its companyId (single-doc get is allowed by
      // the sameCompany read rule).
      final fundSnap0 = await _fundRef(fundId).get();
      if (!fundSnap0.exists) {
        return const Err(ValidationFailure('Fund not found.'));
      }
      final companyId = (fundSnap0.data()!['companyId'] ?? '') as String;
      // COMPANY-SCOPED query (permission-denied fix). Two equality filters only
      // (no composite index needed); status is post-filtered in Dart because
      // release-first cash stays replenishable across released/acknowledged/
      // disputed (see RequestStatus.replenishable) and a `whereIn` here would
      // force a new composite index + deploy.
      final snap = await _requests
          .where('companyId', isEqualTo: companyId)
          .where('fundId', isEqualTo: fundId)
          .get();
      final remainingById = <String, int>{};
      for (final d in snap.docs) {
        if (d.data()['replenishmentId'] != null) continue;
        if (!RequestStatus.fromName(d.data()['status'] as String?)
            .isReplenishable) {
          continue;
        }
        final amount = (d.data()['amountCentavos'] ?? 0) as int;
        final repl = (d.data()['replenishedCentavos'] ?? 0) as int;
        final remaining = amount - repl;
        if (remaining > 0) remainingById[d.id] = remaining;
      }
      // Validate each item and recompute amounts.
      final resolved = <ReplenishmentItem>[];
      var total = Money.zero;
      for (final item in items) {
        final remaining = remainingById[item.requestId];
        if (remaining == null) {
          return const Err(ValidationFailure(
              'Some selected requests are no longer available to replenish.'));
        }
        if (item.isPartial) {
          final c = item.amount.centavos;
          if (c <= 0 || c >= remaining) {
            return const Err(ValidationFailure(
                'A partial amount must be more than zero and less than the remaining balance.'));
          }
          if (item.remarks.trim().isEmpty) {
            return const Err(ValidationFailure('A partial replenishment needs remarks.'));
          }
          resolved.add(ReplenishmentItem(
              requestId: item.requestId,
              isPartial: true,
              amount: Money.fromCentavos(c),
              remarks: item.remarks.trim()));
          total += Money.fromCentavos(c);
        } else {
          // Full: server authority = current remaining (ignore client amount).
          resolved.add(ReplenishmentItem(
              requestId: item.requestId,
              isPartial: false,
              amount: Money.fromCentavos(remaining)));
          total += Money.fromCentavos(remaining);
        }
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
          'companyId': companyId,
          'fundId': fundId,
          'status': ReplenishmentStatus.draft.name,
          'requestIds': resolved.map((i) => i.requestId).toList(),
          'items': resolved.map((i) => i.toMap()).toList(),
          'totalCentavos': total.centavos,
          'reportNotes': '',
          'createdByUid': createdByUid,
          'submittedByUid': null,
          'approvedByUid': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(_fundRef(fundId), {'status': FundStatus.replenishing.name});
      });
      return Ok(Replenishment(
        id: newRef.id,
        companyId: companyId,
        fundId: fundId,
        status: ReplenishmentStatus.draft,
        requestIds: resolved.map((i) => i.requestId).toList(),
        total: total,
        reportNotes: '',
        createdByUid: createdByUid,
        items: resolved,
      ));
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('createDraft failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not start a replenishment.'));
    }
  }

  @override
  Future<Result<void>> createAndSubmit({
    required String fundId,
    required List<ReplenishmentItem> items,
    required String actorUid,
    required String notes,
    String? submitterName,
    String? fundName,
    int? fundAvailableBalanceCentavos,
    int? originalAmountCentavos,
  }) async {
    final draftRes =
        await createDraft(fundId: fundId, items: items, createdByUid: actorUid);
    final draft = draftRes.valueOrNull;
    if (draft == null) return Err(draftRes.failureOrNull!);
    final submitRes = await submit(
      replenishment: draft,
      actorUid: actorUid,
      notes: notes,
      submitterName: submitterName,
      fundName: fundName,
      fundAvailableBalanceCentavos: fundAvailableBalanceCentavos,
      originalAmountCentavos: originalAmountCentavos,
    );
    if (submitRes.failureOrNull != null) {
      // Roll the draft back so the fund isn't left locked in `replenishing`.
      await discardDraft(replenishment: draft);
      return submitRes;
    }
    return const Ok(null);
  }

  @override
  Future<Result<void>> submit({
    required Replenishment replenishment,
    required String actorUid,
    required String notes,
    String? submitterName,
    String? fundName,
    int? fundAvailableBalanceCentavos,
    int? originalAmountCentavos,
  }) async {
    if (!replenishment.status.canTransitionTo(ReplenishmentStatus.submitted)) {
      return const Err(ValidationFailure('Only a draft can be submitted.'));
    }
    try {
      await _reps.doc(replenishment.id).update({
        'status': ReplenishmentStatus.submitted.name,
        'reportNotes': notes,
        'submittedByUid': actorUid,
        'submittedByName': submitterName,
        'submittedAt': FieldValue.serverTimestamp(),
        // Persist the original (pre-partial) total so approve/reject can echo it
        // onto the incharge's outcome notification (additive nullable field).
        'originalAmountCentavos': originalAmountCentavos,
      });
      final companyName = await _resolveCompanyName(replenishment.companyId);
      await _addNotification(
        companyId: replenishment.companyId,
        recipientRoles: const ['superior', 'manager', 'ceo'],
        type: 'replenishmentSubmitted',
        title: 'Replenishment submitted',
        body: 'A replenishment report needs your approval.',
        fundId: replenishment.fundId,
        replenishmentId: replenishment.id,
        fundName: fundName,
        companyName: companyName,
        actorName: submitterName,
        replenishAmountCentavos: replenishment.total.centavos,
        availableBalanceCentavos: fundAvailableBalanceCentavos,
        fillType: computeFill(replenishment.items).name,
        originalAmountCentavos: originalAmountCentavos,
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
    // Captured inside the tx for the post-commit denormalized notification.
    String? fundName;
    int? newBalanceCentavos;
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
        fundName = fund.name;
        // Read every line-item's request BEFORE any write (tx reads-before-writes)
        // and re-validate each against current server state. A stale report must
        // never replenish a request beyond its original amount (and the fund
        // credit equals the sum of these per-item amounts, so this guards the
        // fund too). Validating here — before any write is staged — keeps the
        // whole transaction atomic on rejection.
        final reqData = <String, Map<String, dynamic>>{};
        for (final item in replenishment.items) {
          final rs = await tx.get(_requests.doc(item.requestId));
          if (!rs.exists) {
            throw StateError('A request in this report no longer exists.');
          }
          final data = rs.data()!;
          reqData[item.requestId] = data;
          final amount = (data['amountCentavos'] ?? 0) as int;
          final prior = (data['replenishedCentavos'] ?? 0) as int;
          if (prior + item.amount.centavos > amount) {
            throw StateError('A request in this report was already replenished.');
          }
        }
        // --- writes ---
        final newBalance = fund.availableBalance + replenishment.total;
        newBalanceCentavos = newBalance.centavos;
        final replenished = Fund(
          id: fund.id,
          companyId: fund.companyId,
          name: fund.name,
          originalBudget: fund.originalBudget,
          availableBalance: newBalance,
          lowBalanceThresholdPct: fund.lowBalanceThresholdPct,
          status: fund.status,
        );
        tx.update(_fundRef(replenishment.fundId), {
          'availableBalanceCentavos': newBalance.centavos,
          'status': _restoredStatus(replenished).name,
        });
        for (final item in replenishment.items) {
          final reqRef = _requests.doc(item.requestId);
          final prior = (reqData[item.requestId]?['replenishedCentavos'] ?? 0) as int;
          final nextReplenished = prior + item.amount.centavos;
          if (item.isPartial) {
            tx.set(_partials.doc(), {
              'companyId': replenishment.companyId,
              'fundId': replenishment.fundId,
              'requestId': item.requestId,
              'replenishmentId': replenishment.id,
              'amountCentavos': item.amount.centavos,
              'remarks': item.remarks,
              'createdByUid': replenishment.createdByUid,
              'approvedByUid': actorUid,
              'createdAt': FieldValue.serverTimestamp(),
            });
            tx.update(reqRef, {'replenishedCentavos': nextReplenished});
          } else {
            tx.update(reqRef, {
              'status': RequestStatus.replenished.name,
              'replenishmentId': replenishment.id,
              'replenishedCentavos': nextReplenished,
            });
          }
        }
        tx.update(repRef, {
          'status': ReplenishmentStatus.approved.name,
          'approvedByUid': actorUid,
          'decidedAt': FieldValue.serverTimestamp(),
        });
      });
      final companyName = await _resolveCompanyName(replenishment.companyId);
      await _addNotification(
        companyId: replenishment.companyId,
        recipientRoles: const ['incharge'],
        type: 'replenishmentApproved',
        title: 'Replenishment approved',
        body: 'The fund has been replenished and is ready for requests.',
        fundId: replenishment.fundId,
        replenishmentId: replenishment.id,
        fundName: fundName,
        companyName: companyName,
        actorName: replenishment.submittedByName,
        replenishAmountCentavos: replenishment.total.centavos,
        // POST-credit balance — the figure the incharge most cares about.
        availableBalanceCentavos: newBalanceCentavos,
        fillType: computeFill(replenishment.items).name,
        // Echo the original (pre-partial) total persisted at submit time.
        originalAmountCentavos: replenishment.originalAmountCentavos,
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
    // Captured inside the tx for the post-commit denormalized notification.
    String? fundName;
    int? balanceCentavos;
    try {
      await _db.runTransaction((tx) async {
        final fundSnap = await tx.get(_fundRef(replenishment.fundId));
        if (!fundSnap.exists) throw StateError('Fund not found.');
        final fund = Fund.fromMap(fundSnap.id, fundSnap.data()!);
        fundName = fund.name;
        // Reject does not credit the fund — the balance is unchanged.
        balanceCentavos = fund.availableBalance.centavos;
        tx.update(_fundRef(replenishment.fundId), {'status': _restoredStatus(fund).name});
        tx.update(_reps.doc(replenishment.id), {
          'status': ReplenishmentStatus.rejected.name,
          'approvedByUid': actorUid,
          'decidedAt': FieldValue.serverTimestamp(),
        });
      });
      final companyName = await _resolveCompanyName(replenishment.companyId);
      await _addNotification(
        companyId: replenishment.companyId,
        recipientRoles: const ['incharge'],
        type: 'replenishmentRejected',
        title: 'Replenishment rejected',
        body: 'Your replenishment report was rejected.',
        fundId: replenishment.fundId,
        replenishmentId: replenishment.id,
        fundName: fundName,
        companyName: companyName,
        actorName: replenishment.submittedByName,
        replenishAmountCentavos: replenishment.total.centavos,
        // Unchanged balance — reject does not credit the fund.
        availableBalanceCentavos: balanceCentavos,
        fillType: computeFill(replenishment.items).name,
        // Echo the original (pre-partial) total persisted at submit time.
        originalAmountCentavos: replenishment.originalAmountCentavos,
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
        final repRef = _reps.doc(replenishment.id);
        final repSnap = await tx.get(repRef);
        if (!repSnap.exists) throw StateError('Replenishment not found.');
        final current = ReplenishmentStatus.fromName(repSnap.data()!['status'] as String?);
        if (current != ReplenishmentStatus.draft) {
          throw StateError('This draft was already acted on.');
        }
        final fundSnap = await tx.get(_fundRef(replenishment.fundId));
        if (fundSnap.exists) {
          final fund = Fund.fromMap(fundSnap.id, fundSnap.data()!);
          tx.update(_fundRef(replenishment.fundId),
              {'status': _restoredStatus(fund).name});
        }
        tx.update(repRef, {'status': ReplenishmentStatus.rejected.name});
      });
      return const Ok(null);
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('discardDraft failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not discard the draft.'));
    }
  }

  @override
  Future<Result<Replenishment>> getById(String id) async {
    try {
      final snap = await _reps.doc(id).get();
      if (!snap.exists) {
        return const Err(NotFoundFailure('This replenishment is no longer available.'));
      }
      return Ok(Replenishment.fromMap(snap.id, snap.data()!));
    } catch (e, st) {
      developer.log('getById failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not load the replenishment.'));
    }
  }

  /// Best-effort company-name lookup for notification denormalization. A failure
  /// (offline, permission, missing doc) returns null so the notification still
  /// writes — companyName simply stays null. Never throws; never reads inside a
  /// money transaction.
  Future<String?> _resolveCompanyName(String companyId) async {
    try {
      final snap = await _db.collection('companies').doc(companyId).get();
      if (!snap.exists) return null;
      return (snap.data()?['name'] ?? '') as String?;
    } catch (e, st) {
      developer.log('company name lookup failed',
          name: 'replenishment', error: e, stackTrace: st);
      return null;
    }
  }

  /// Derives fund status (active/low) from the given fund's balance. Used when a
  /// replenishment is rejected/discarded (unchanged balance) and on approval
  /// (a fund carrying the new, added-back balance). The prior status is not
  /// preserved verbatim; it is derived from balance, which is self-consistent
  /// with FundStatus semantics.
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
    String? fundName,
    String? companyName,
    String? actorName,
    int? replenishAmountCentavos,
    int? availableBalanceCentavos,
    String? fillType,
    int? originalAmountCentavos,
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
        'fundName': fundName,
        'companyName': companyName,
        'actorName': actorName,
        'replenishAmountCentavos': replenishAmountCentavos,
        'availableBalanceCentavos': availableBalanceCentavos,
        'fillType': fillType,
        'originalAmountCentavos': originalAmountCentavos,
        'readAt': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      developer.log('notification write failed', name: 'replenishment', error: e, stackTrace: st);
    }
    // Best-effort push for the same audience/text. Not awaited; failures are
    // swallowed by the sender and never affect the triggering operation.
    unawaited(_push.notify(
      companyId: companyId,
      recipientRoles: recipientRoles,
      title: title,
      body: body,
    ));
  }
}
