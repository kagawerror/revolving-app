import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/data/firestore_replenishment_repository.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';

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
    final rp = await db.collection('replenishments').doc(res.valueOrNull!).get();
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
    final id = (await repo.createDraft(fundId: 'f1', createdByUid: 'inc')).valueOrNull!;
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
    final id = (await repo.createDraft(fundId: 'f1', createdByUid: 'inc')).valueOrNull!;
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
    final id = (await repo.createDraft(fundId: 'f1', createdByUid: 'inc')).valueOrNull!;
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
}
