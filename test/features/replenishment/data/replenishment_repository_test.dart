import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/data/firestore_replenishment_repository.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('funds').doc('f1').set({
      'companyId': 'c1', 'name': 'PC',
      'originalBudgetCentavos': 10000000, 'availableBalanceCentavos': 200000,
      'lowBalanceThresholdPct': 3, 'status': 'low',
    });
    for (final id in ['r1', 'r2']) {
      await db.collection('requests').doc(id).set({
        'companyId': 'c1', 'fundId': 'f1', 'createdByUid': 'inc',
        'beneficiaryName': 'B', 'amountCentavos': 400000, 'purpose': 'x',
        'proofImageUrl': 'http://img', 'status': 'released', 'replenishmentId': null,
      });
    }
  });

  test('createDraft compiles released-unreplenished requests and flips fund to replenishing', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(fundId: 'f1', createdByUid: 'inc');
    expect(res.isOk, isTrue);
    final rp = await db.collection('replenishments').doc(res.valueOrNull!.id).get();
    expect((rp.data()!['requestIds'] as List).length, 2);
    expect(rp.data()!['totalCentavos'], 800000);
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['status'], 'replenishing');
  });

  test('createDraft fails when fund already replenishing', () async {
    await db.collection('funds').doc('f1').update({'status': 'replenishing'});
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(fundId: 'f1', createdByUid: 'inc');
    expect(res.failureOrNull, isA<ValidationFailure>());
  });

  test('approve resets balance to ceiling, tags requests replenished, fund active', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final id = (await repo.createDraft(fundId: 'f1', createdByUid: 'inc')).valueOrNull!.id;
    final draft = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    await repo.submit(replenishment: draft, actorUid: 'inc', notes: 'June');
    final submitted = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    final res = await repo.approve(replenishment: submitted, actorUid: 'mgr');
    expect(res.isOk, isTrue);
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 10000000); // reset to ceiling
    expect(fund.data()!['status'], 'active');
    for (final rid in ['r1', 'r2']) {
      final req = await db.collection('requests').doc(rid).get();
      expect(req.data()!['status'], 'replenished');
      expect(req.data()!['replenishmentId'], id);
    }
    final rp = await db.collection('replenishments').doc(id).get();
    expect(rp.data()!['status'], 'approved');
  });

  test('double-approval of a stale submitted object is rejected in-tx', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final id = (await repo.createDraft(fundId: 'f1', createdByUid: 'inc')).valueOrNull!.id;
    final draft = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    await repo.submit(replenishment: draft, actorUid: 'inc', notes: 'June');
    final submitted = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    final first = await repo.approve(replenishment: submitted, actorUid: 'mgr');
    expect(first.isOk, isTrue);
    // Re-approve the SAME stale submitted object: the in-tx re-check rejects it.
    final second = await repo.approve(replenishment: submitted, actorUid: 'mgr');
    expect(second.failureOrNull, isA<ValidationFailure>());
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 10000000); // stays at ceiling
  });

  test('reject restores status to low and leaves requests released', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final id = (await repo.createDraft(fundId: 'f1', createdByUid: 'inc')).valueOrNull!.id;
    final draft = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    await repo.submit(replenishment: draft, actorUid: 'inc', notes: 'June');
    final submitted = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    final res = await repo.reject(replenishment: submitted, actorUid: 'mgr');
    expect(res.isOk, isTrue);
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['status'], 'low'); // 200000 <= 3% of 10000000 = 300000
    final rp = await db.collection('replenishments').doc(id).get();
    expect(rp.data()!['status'], 'rejected');
    for (final rid in ['r1', 'r2']) {
      final req = await db.collection('requests').doc(rid).get();
      expect(req.data()!['status'], 'released');
      expect(req.data()!['replenishmentId'], isNull);
    }
  });

  test('submit rejects a non-draft replenishment', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final rep = Replenishment(
      id: 'x1',
      companyId: 'c1',
      fundId: 'f1',
      status: ReplenishmentStatus.approved,
      requestIds: const ['r1'],
      total: Money.fromCentavos(400000),
      reportNotes: '',
      createdByUid: 'inc',
    );
    final res = await repo.submit(replenishment: rep, actorUid: 'inc', notes: 'x');
    expect(res.failureOrNull, isA<ValidationFailure>());
  });

  test('createDraft fails with no released requests for the fund', () async {
    await db.collection('funds').doc('f2').set({
      'companyId': 'c1', 'name': 'PC2',
      'originalBudgetCentavos': 10000000, 'availableBalanceCentavos': 10000000,
      'lowBalanceThresholdPct': 3, 'status': 'active',
    });
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(fundId: 'f2', createdByUid: 'inc');
    expect(res.failureOrNull, isA<ValidationFailure>());
    expect((res.failureOrNull as ValidationFailure).message,
        'No released requests to replenish.');
  });

  // End-to-end money loop driven through the REAL repositories (not a
  // pre-seeded 'released' status): release -> createDraft -> submit -> approve.
  // This exercises the cross-repository contract: a release debits the fund and
  // marks the request 'released'; createDraft compiles released-unreplenished
  // requests; approve resets the balance and stamps each request 'replenished'.
  //
  // NOTE: fake_cloud_firestore does NOT enforce security rules, so this test
  // validates repository logic ONLY. The firestore.rules branch permitting an
  // approver to drive a request from 'released' -> 'replenished' must still be
  // verified against the emulator or in production manually.
  test('end-to-end: release -> createDraft -> approve resets the fund', () async {
    db = FakeFirebaseFirestore();
    await db.collection('funds').doc('f1').set({
      'companyId': 'c1', 'name': 'PC',
      'originalBudgetCentavos': 10000000, 'availableBalanceCentavos': 500000,
      'lowBalanceThresholdPct': 3, 'status': 'active',
    });
    await db.collection('requests').doc('r1').set({
      'companyId': 'c1', 'fundId': 'f1', 'createdByUid': 'inc',
      'beneficiaryName': 'B', 'amountCentavos': 400000, 'purpose': 'x',
      'proofImageUrl': 'http://img', 'status': 'readyForRelease',
      'replenishmentId': null,
    });

    final requestRepo = FirestoreRequestRepository(db);
    final replenishRepo = FirestoreReplenishmentRepository(db);

    // 1. Release r1: fund 500000 - 400000 = 100000, which is <= 3% of
    //    10000000 (= 300000), so the fund flips to 'low'.
    final r1 = FundRequest.fromMap(
        'r1', (await db.collection('requests').doc('r1').get()).data()!);
    final released = await requestRepo.release(request: r1, actorUid: 'inc');
    expect(released.isOk, isTrue);
    var fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 100000);
    expect(fund.data()!['status'], 'low');
    final r1AfterRelease = await db.collection('requests').doc('r1').get();
    expect(r1AfterRelease.data()!['status'], 'released');

    // 2. Compile the draft from released-unreplenished requests.
    final draftRes = await replenishRepo.createDraft(fundId: 'f1', createdByUid: 'inc');
    expect(draftRes.isOk, isTrue);
    final draft = draftRes.valueOrNull!;
    expect(draft.requestIds, contains('r1'));
    expect(draft.total.centavos, 400000);
    fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['status'], 'replenishing');

    // 3. Submit then approve.
    final submitRes = await replenishRepo.submit(
        replenishment: draft, actorUid: 'inc', notes: 'June');
    expect(submitRes.isOk, isTrue);
    final submitted = Replenishment.fromMap(draft.id,
        (await db.collection('replenishments').doc(draft.id).get()).data()!);
    final approveRes = await replenishRepo.approve(
        replenishment: submitted, actorUid: 'mgr');
    expect(approveRes.isOk, isTrue);

    // 4. Fund is fully restored; request is 'replenished' and tagged.
    fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 10000000);
    expect(fund.data()!['status'], 'active');
    final r1Final = await db.collection('requests').doc('r1').get();
    expect(r1Final.data()!['status'], 'replenished');
    expect(r1Final.data()!['replenishmentId'], draft.id);
  });
}
