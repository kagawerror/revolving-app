import 'package:cloud_firestore/cloud_firestore.dart';
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
  ReplenishmentItem full(String id) =>
      ReplenishmentItem(requestId: id, isPartial: false, amount: Money.zero);
  ReplenishmentItem partial(String id, int centavos, String remarks) =>
      ReplenishmentItem(
          requestId: id,
          isPartial: true,
          amount: Money.fromCentavos(centavos),
          remarks: remarks);

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

  test('createDraft compiles the selected released requests and flips fund to replenishing', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1', items: [full('r1'), full('r2')], createdByUid: 'inc');
    expect(res.isOk, isTrue);
    final rp = await db.collection('replenishments').doc(res.valueOrNull!.id).get();
    expect((rp.data()!['requestIds'] as List).length, 2);
    expect(rp.data()!['totalCentavos'], 800000);
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['status'], 'replenishing');
  });

  test('createDraft includes acknowledged & disputed (post-release) requests, '
      'not just released', () async {
    // Release-first lifecycle: cash is handed out (fund debited, status
    // "released"), THEN an approver acknowledges or disputes on sync. That
    // already-released cash is still owed back to the fund, so it must remain
    // replenishable. Regression for the offline-first replenish-sheet bug.
    await db.collection('requests').doc('r1').update({'status': 'acknowledged'});
    await db.collection('requests').doc('r2').update({'status': 'disputed'});
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1', items: [full('r1'), full('r2')], createdByUid: 'inc');
    expect(res.isOk, isTrue);
    expect(res.valueOrNull!.requestIds.toSet(), {'r1', 'r2'});
    expect(res.valueOrNull!.total.centavos, 800000);
  });

  test('createDraft still excludes non-replenishable statuses (created, '
      'rejected, replenished)', () async {
    await db.collection('requests').doc('r1').update({'status': 'created'});
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1', items: [full('r1')], createdByUid: 'inc');
    expect(res.failureOrNull, isA<ValidationFailure>());
    expect((res.failureOrNull as ValidationFailure).message,
        'Some selected requests are no longer available to replenish.');
  });

  test('createDraft fails when fund already replenishing', () async {
    await db.collection('funds').doc('f1').update({'status': 'replenishing'});
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1', items: [full('r1'), full('r2')], createdByUid: 'inc');
    expect(res.failureOrNull, isA<ValidationFailure>());
  });

  // Helper: seed an already-`submitted` report directly (a legacy in-flight
  // doc), so the legacy approve()/reject() drain paths can be exercised even
  // though the new submit() auto-approves and never produces `submitted`.
  Future<String> seedSubmitted({
    List<String> requestIds = const ['r1', 'r2'],
    int totalCentavos = 800000,
    String? submittedByName,
    int? originalAmountCentavos,
    List<ReplenishmentItem>? items,
  }) async {
    // Default to FULL items for each requestId so the legacy approve() drain
    // (which reads each line item) has something to tag. r1/r2 each owe 400000.
    final resolvedItems = items ??
        [for (final id in requestIds) full(id).copyWithAmount(400000)];
    final ref = db.collection('replenishments').doc();
    await ref.set({
      'companyId': 'c1', 'fundId': 'f1', 'status': 'submitted',
      'requestIds': requestIds, 'totalCentavos': totalCentavos,
      'reportNotes': 'June', 'createdByUid': 'inc',
      'submittedByUid': 'inc', 'submittedByName': submittedByName,
      'originalAmountCentavos': originalAmountCentavos,
      'items': resolvedItems.map((i) => i.toMap()).toList(),
    });
    return ref.id;
  }

  test('submit auto-approves a draft: credits the fund, tags requests, sets '
      'approved + autoApproved + acknowledgedByUid null', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final id = (await repo.createDraft(
            fundId: 'f1', items: [full('r1'), full('r2')], createdByUid: 'inc'))
        .valueOrNull!
        .id;
    final draft = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    final res = await repo.submit(
        replenishment: draft, actorUid: 'inc', notes: 'June');
    expect(res.isOk, isTrue);
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 1000000); // 200000 + 800000
    expect(fund.data()!['status'], 'active');
    for (final rid in ['r1', 'r2']) {
      final req = await db.collection('requests').doc(rid).get();
      expect(req.data()!['status'], 'replenished');
      expect(req.data()!['replenishmentId'], id);
    }
    final rp = await db.collection('replenishments').doc(id).get();
    expect(rp.data()!['status'], 'approved');
    expect(rp.data()!['autoApproved'], true);
    expect(rp.data()!['acknowledgedByUid'], isNull);
  });

  test('double-submit of a stale draft object is rejected in-tx', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final id = (await repo.createDraft(
            fundId: 'f1', items: [full('r1'), full('r2')], createdByUid: 'inc'))
        .valueOrNull!
        .id;
    final draft = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    final first = await repo.submit(
        replenishment: draft, actorUid: 'inc', notes: 'June');
    expect(first.isOk, isTrue);
    // Re-submit the SAME stale draft object: the in-tx re-check rejects it.
    final second = await repo.submit(
        replenishment: draft, actorUid: 'inc', notes: 'June');
    expect(second.failureOrNull, isA<ValidationFailure>());
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 1000000); // stays after first
  });

  test('acknowledge stamps fields, keeps status approved; second call is a '
      'no-op Ok', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final id = (await repo.createDraft(
            fundId: 'f1', items: [full('r1'), full('r2')], createdByUid: 'inc'))
        .valueOrNull!
        .id;
    final draft = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    await repo.submit(replenishment: draft, actorUid: 'inc', notes: 'June');
    final approved = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    expect(approved.needsAcknowledgment, isTrue);

    final ack = await repo.acknowledge(
        replenishment: approved, actorUid: 'mgr', actorName: 'Mona Manager');
    expect(ack.isOk, isTrue);
    final rp = await db.collection('replenishments').doc(id).get();
    expect(rp.data()!['status'], 'approved'); // unchanged
    expect(rp.data()!['acknowledgedByUid'], 'mgr');
    expect(rp.data()!['acknowledgedByName'], 'Mona Manager');
    expect(rp.data()!['acknowledgedAt'], isNotNull);

    // Second call on the now-acknowledged doc is an idempotent no-op.
    final acked = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    final second = await repo.acknowledge(
        replenishment: acked, actorUid: 'other', actorName: 'X');
    expect(second.isOk, isTrue);
    final rp2 = await db.collection('replenishments').doc(id).get();
    expect(rp2.data()!['acknowledgedByUid'], 'mgr'); // unchanged
  });

  test('acknowledge errs when the report is not approved', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final rep = Replenishment(
      id: 'x1', companyId: 'c1', fundId: 'f1',
      status: ReplenishmentStatus.draft,
      requestIds: const ['r1'], total: Money.fromCentavos(400000),
      reportNotes: '', createdByUid: 'inc',
    );
    final res = await repo.acknowledge(replenishment: rep, actorUid: 'mgr');
    expect(res.failureOrNull, isA<ValidationFailure>());
  });

  test('LEGACY approve still drains a submitted doc', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final id = await seedSubmitted();
    final submitted = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    final res = await repo.approve(replenishment: submitted, actorUid: 'mgr');
    expect(res.isOk, isTrue);
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 1000000); // 200000 + 800000
    expect(fund.data()!['status'], 'active');
    for (final rid in ['r1', 'r2']) {
      final req = await db.collection('requests').doc(rid).get();
      expect(req.data()!['status'], 'replenished');
    }
    final rp = await db.collection('replenishments').doc(id).get();
    expect(rp.data()!['status'], 'approved');
  });

  test('LEGACY double-approval of a stale submitted object is rejected in-tx',
      () async {
    final repo = FirestoreReplenishmentRepository(db);
    final id = await seedSubmitted();
    final submitted = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    final first = await repo.approve(replenishment: submitted, actorUid: 'mgr');
    expect(first.isOk, isTrue);
    final second = await repo.approve(replenishment: submitted, actorUid: 'mgr');
    expect(second.failureOrNull, isA<ValidationFailure>());
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 1000000);
  });

  test('LEGACY reject restores status to low and leaves requests released',
      () async {
    final repo = FirestoreReplenishmentRepository(db);
    final id = await seedSubmitted();
    final submitted = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    final res = await repo.reject(
        replenishment: submitted,
        actorUid: 'mgr',
        reason: 'A valid rejection reason for this report.');
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

  test('LEGACY reject persists the rejection reason + actor and does not credit '
      'the fund', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final id = await seedSubmitted();
    final submitted = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    const reason = 'Receipts do not match the claimed total amount.';
    final res = await repo.reject(
        replenishment: submitted, actorUid: 'mgr', reason: reason);
    expect(res.isOk, isTrue);
    final rp = await db.collection('replenishments').doc(id).get();
    expect(rp.data()!['status'], 'rejected');
    expect(rp.data()!['rejectionReason'], reason);
    expect(rp.data()!['rejectedByUid'], 'mgr');
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 200000);
  });

  test('reject of a non-submitted report returns an Err', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final rep = Replenishment(
      id: 'x1',
      companyId: 'c1',
      fundId: 'f1',
      status: ReplenishmentStatus.draft,
      requestIds: const ['r1'],
      total: Money.fromCentavos(400000),
      reportNotes: '',
      createdByUid: 'inc',
    );
    final res = await repo.reject(
        replenishment: rep,
        actorUid: 'mgr',
        reason: 'A perfectly valid rejection reason here.');
    expect(res.failureOrNull, isA<ValidationFailure>());
  });

  test('getById returns Ok for an existing replenishment', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final id = (await repo.createDraft(
            fundId: 'f1', items: [full('r1')], createdByUid: 'inc'))
        .valueOrNull!
        .id;
    final res = await repo.getById(id);
    expect(res.isOk, isTrue);
    expect(res.valueOrNull!.id, id);
  });

  test('getById returns NotFoundFailure for a missing replenishment', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.getById('nope');
    expect(res.failureOrNull, isA<NotFoundFailure>());
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

  test('submit auto-approve denormalizes the needs-acknowledgment notification',
      () async {
    await db.collection('companies').doc('c1').set({'name': 'Acme Corp'});
    final repo = FirestoreReplenishmentRepository(db);
    final id = (await repo.createDraft(
            fundId: 'f1',
            items: [full('r1'), partial('r2', 100000, 'half')],
            createdByUid: 'inc'))
        .valueOrNull!
        .id;
    final draft = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);

    final res = await repo.submit(
      replenishment: draft,
      actorUid: 'inc',
      notes: 'June',
      submitterName: 'Ada Incharge',
      fundName: 'PC',
      fundAvailableBalanceCentavos: 200000,
      originalAmountCentavos: 750000,
    );
    expect(res.isOk, isTrue);

    // submittedByName + originalAmountCentavos landed on the report.
    final rp = await db.collection('replenishments').doc(id).get();
    expect(rp.data()!['submittedByName'], 'Ada Incharge');
    expect(rp.data()!['originalAmountCentavos'], 750000);
    expect(rp.data()!['status'], 'approved');

    // The needs-ack notification (replaces replenishmentSubmitted) carries the
    // denormalized display fields and the POST-credit balance.
    final notifs = await db
        .collection('notifications')
        .where('type', isEqualTo: 'replenishmentNeedsAck')
        .get();
    expect(notifs.docs.length, 1);
    final n = notifs.docs.first.data();
    expect(n['fundName'], 'PC');
    expect(n['companyName'], 'Acme Corp');
    expect(n['actorName'], 'Ada Incharge');
    // Full r1 (400000) + partial r2 (100000) = 500000.
    expect(n['replenishAmountCentavos'], 500000);
    // POST-credit balance: 200000 + 500000.
    expect(n['availableBalanceCentavos'], 700000);
    expect(n['fillType'], 'mixed');
    expect(n['originalAmountCentavos'], 750000);
    expect((n['recipientRoles'] as List),
        ['admin', 'superior', 'manager', 'ceo']);
    // No legacy replenishmentSubmitted alert is emitted on the new path.
    final legacy = await db
        .collection('notifications')
        .where('type', isEqualTo: 'replenishmentSubmitted')
        .get();
    expect(legacy.docs, isEmpty);
  });

  test('acknowledge notifies the incharge', () async {
    await db.collection('companies').doc('c1').set({'name': 'Acme Corp'});
    final repo = FirestoreReplenishmentRepository(db);
    final id = (await repo.createDraft(
            fundId: 'f1', items: [full('r1'), full('r2')], createdByUid: 'inc'))
        .valueOrNull!
        .id;
    final draft = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    await repo.submit(replenishment: draft, actorUid: 'inc', notes: 'June');
    final approved = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    await repo.acknowledge(
        replenishment: approved, actorUid: 'mgr', actorName: 'Mona Manager');

    final notifs = await db
        .collection('notifications')
        .where('type', isEqualTo: 'replenishmentAcknowledged')
        .get();
    expect(notifs.docs.length, 1);
    final n = notifs.docs.first.data();
    expect((n['recipientRoles'] as List), ['incharge']);
    expect(n['actorName'], 'Mona Manager');
  });

  test('LEGACY reject denormalizes the incharge notification with unchanged '
      'balance', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final id = await seedSubmitted(
        requestIds: const ['r1'],
        totalCentavos: 400000,
        submittedByName: 'Ada Incharge');
    final submitted = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    final res = await repo.reject(
        replenishment: submitted,
        actorUid: 'mgr',
        reason: 'A valid rejection reason for this report.');
    expect(res.isOk, isTrue);

    final notifs = await db
        .collection('notifications')
        .where('type', isEqualTo: 'replenishmentRejected')
        .get();
    final n = notifs.docs.first.data();
    expect(n['actorName'], 'Ada Incharge');
    // Reject does not credit — balance stays at 200000.
    expect(n['availableBalanceCentavos'], 200000);
  });

  test('watchByStatusAll returns submitted reps across all companies, excluding other statuses',
      () async {
    db = FakeFirebaseFirestore();
    final repo = FirestoreReplenishmentRepository(db);
    await db.collection('replenishments').doc('a').set({
      'companyId': 'c1', 'fundId': 'f', 'status': 'submitted',
      'requestIds': const ['r1'], 'totalCentavos': 100, 'reportNotes': '',
      'createdByUid': 'inc',
    });
    await db.collection('replenishments').doc('b').set({
      'companyId': 'c2', 'fundId': 'f', 'status': 'submitted',
      'requestIds': const ['r2'], 'totalCentavos': 100, 'reportNotes': '',
      'createdByUid': 'inc',
    });
    await db.collection('replenishments').doc('c').set({
      'companyId': 'c1', 'fundId': 'f', 'status': 'draft',
      'requestIds': const ['r3'], 'totalCentavos': 100, 'reportNotes': '',
      'createdByUid': 'inc',
    });

    final list = await repo.watchByStatusAll('submitted').first;
    final ids = list.map((r) => r.id).toSet();
    expect(ids, {'a', 'b'});
    expect(list.every((r) => r.status == ReplenishmentStatus.submitted), isTrue);
  });

  group('watchByCompanyAndStatusRecent', () {
    // Explicit Timestamps (NOT serverTimestamp): the fake resolves
    // serverTimestamp lazily, which makes orderBy on createdAt unreliable.
    Future<void> seedRep(
      String id, {
      required String companyId,
      required String status,
      required DateTime createdAt,
    }) =>
        db.collection('replenishments').doc(id).set({
          'companyId': companyId, 'fundId': 'f', 'status': status,
          'requestIds': const ['r'], 'totalCentavos': 100, 'reportNotes': '',
          'createdByUid': 'inc',
          'createdAt': Timestamp.fromDate(createdAt),
        });

    test('returns only approved for the company, newest-first', () async {
      db = FakeFirebaseFirestore();
      final repo = FirestoreReplenishmentRepository(db);
      await seedRep('old', companyId: 'c1', status: 'approved', createdAt: DateTime(2026, 1, 1));
      await seedRep('new', companyId: 'c1', status: 'approved', createdAt: DateTime(2026, 1, 5));
      await seedRep('sub', companyId: 'c1', status: 'submitted', createdAt: DateTime(2026, 1, 9));
      await seedRep('other', companyId: 'c2', status: 'approved', createdAt: DateTime(2026, 1, 7));

      final list =
          await repo.watchByCompanyAndStatusRecent('c1', 'approved', 25).first;

      expect(list.map((r) => r.id).toList(), ['new', 'old']);
      expect(list.every((r) => r.companyId == 'c1'), isTrue);
      expect(list.every((r) => r.status == ReplenishmentStatus.approved), isTrue);
    });

    test('respects the limit, keeping the newest', () async {
      db = FakeFirebaseFirestore();
      final repo = FirestoreReplenishmentRepository(db);
      await seedRep('a', companyId: 'c1', status: 'approved', createdAt: DateTime(2026, 1, 1));
      await seedRep('b', companyId: 'c1', status: 'approved', createdAt: DateTime(2026, 1, 3));
      await seedRep('c', companyId: 'c1', status: 'approved', createdAt: DateTime(2026, 1, 2));

      final list =
          await repo.watchByCompanyAndStatusRecent('c1', 'approved', 2).first;

      expect(list.map((r) => r.id).toList(), ['b', 'c']);
    });
  });

  test('createDraft fails with no released requests for the fund', () async {
    await db.collection('funds').doc('f2').set({
      'companyId': 'c1', 'name': 'PC2',
      'originalBudgetCentavos': 10000000, 'availableBalanceCentavos': 10000000,
      'lowBalanceThresholdPct': 3, 'status': 'active',
    });
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f2', items: [full('rX')], createdByUid: 'inc');
    expect(res.failureOrNull, isA<ValidationFailure>());
    expect((res.failureOrNull as ValidationFailure).message,
        'Some selected requests are no longer available to replenish.');
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
  test('end-to-end: release -> createDraft -> approve adds the total back to the fund', () async {
    db = FakeFirebaseFirestore();
    await db.collection('funds').doc('f1').set({
      'companyId': 'c1', 'name': 'PC',
      'originalBudgetCentavos': 10000000, 'availableBalanceCentavos': 500000,
      'lowBalanceThresholdPct': 3, 'status': 'active',
    });
    await db.collection('requests').doc('r1').set({
      'companyId': 'c1', 'fundId': 'f1', 'createdByUid': 'inc',
      'beneficiaryName': 'B', 'amountCentavos': 400000, 'purpose': 'x',
      'proofImageUrl': 'http://img', 'status': 'created',
      'replenishmentId': null,
    });

    final requestRepo = FirestoreRequestRepository(db);
    final replenishRepo = FirestoreReplenishmentRepository(db);

    // 1. Release r1: fund 500000 - 400000 = 100000, which is <= 3% of
    //    10000000 (= 300000), so the fund flips to 'low'.
    final r1 = FundRequest.fromMap(
        'r1', (await db.collection('requests').doc('r1').get()).data()!);
    final released = await requestRepo.release(
      request: r1,
      actorUid: 'inc',
      releaseProofUrl: 'https://img/release.jpg',
      releaseSignatureUrl: 'https://img/sig.png',
      clientReleaseId: 'cid-test',
    );
    expect(released.isOk, isTrue);
    var fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 100000);
    expect(fund.data()!['status'], 'low');
    final r1AfterRelease = await db.collection('requests').doc('r1').get();
    expect(r1AfterRelease.data()!['status'], 'released');

    // 2. Compile the draft from released-unreplenished requests.
    final draftRes = await replenishRepo.createDraft(
        fundId: 'f1', items: [full('r1')], createdByUid: 'inc');
    expect(draftRes.isOk, isTrue);
    final draft = draftRes.valueOrNull!;
    expect(draft.requestIds, contains('r1'));
    expect(draft.total.centavos, 400000);
    fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['status'], 'replenishing');

    // 3. Submit auto-approves: the incharge's submit credits the fund.
    final submitRes = await replenishRepo.submit(
        replenishment: draft, actorUid: 'inc', notes: 'June');
    expect(submitRes.isOk, isTrue);

    // 4. Fund is fully restored; request is 'replenished' and tagged.
    fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 500000); // 100000 + 400000
    expect(fund.data()!['status'], 'active');
    final r1Final = await db.collection('requests').doc('r1').get();
    expect(r1Final.data()!['status'], 'replenished');
    expect(r1Final.data()!['replenishmentId'], draft.id);
  });

  test('createDraft sums only the selected requests', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1', items: [full('r1')], createdByUid: 'inc');
    expect(res.isOk, isTrue);
    expect(res.valueOrNull!.requestIds, const ['r1']);
    expect(res.valueOrNull!.total.centavos, 400000); // not 800000
  });

  test('createDraft rejects an empty selection without touching the fund', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1', items: const <ReplenishmentItem>[], createdByUid: 'inc');
    expect(res.failureOrNull, isA<ValidationFailure>());
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['status'], 'low'); // unchanged
  });

  test('createDraft rejects a selection that includes a non-releasable id', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1', items: [full('r1'), full('ghost')], createdByUid: 'inc');
    expect(res.failureOrNull, isA<ValidationFailure>());
    expect((res.failureOrNull as ValidationFailure).message,
        'Some selected requests are no longer available to replenish.');
  });

  test('createAndSubmit auto-approves: credits the fund and lands approved',
      () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createAndSubmit(
        fundId: 'f1', items: [full('r1'), full('r2')], actorUid: 'inc', notes: 'June');
    expect(res.isOk, isTrue);
    final reps = await db
        .collection('replenishments')
        .where('fundId', isEqualTo: 'f1')
        .get();
    expect(reps.docs.length, 1);
    expect(reps.docs.single.data()['status'], 'approved');
    expect(reps.docs.single.data()['autoApproved'], true);
    expect(reps.docs.single.data()['reportNotes'], 'June');
    final fund = await db.collection('funds').doc('f1').get();
    // 200000 + 800000 = 1000000; above the 3% low threshold -> active.
    expect(fund.data()!['availableBalanceCentavos'], 1000000);
    expect(fund.data()!['status'], 'active');
  });

  test('createAndSubmit propagates a createDraft failure and creates nothing', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createAndSubmit(
        fundId: 'f1', items: const <ReplenishmentItem>[], actorUid: 'inc', notes: '');
    expect(res.failureOrNull, isA<ValidationFailure>());
    final reps = await db.collection('replenishments').get();
    expect(reps.docs, isEmpty);
  });

  test('createDraft: a full item ignores client amount and uses remaining', () async {
    // r1 already partly replenished: amount 400000, replenished 150000 -> remaining 250000.
    await db.collection('requests').doc('r1').update({'replenishedCentavos': 150000});
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1',
        // pass a bogus client amount on the full item; server must override.
        items: [full('r1').copyWithAmount(999999)],
        createdByUid: 'inc');
    expect(res.isOk, isTrue);
    expect(res.valueOrNull!.items.single.isPartial, isFalse);
    expect(res.valueOrNull!.items.single.amount.centavos, 250000); // remaining, not 999999
    expect(res.valueOrNull!.total.centavos, 250000);
  });

  test('createDraft: partial must be > 0 and < remaining', () async {
    final repo = FirestoreReplenishmentRepository(db);
    // r1 remaining is 400000.
    final tooBig = await repo.createDraft(
        fundId: 'f1', items: [partial('r1', 400000, 'x')], createdByUid: 'inc');
    expect(tooBig.failureOrNull, isA<ValidationFailure>());
    final zero = await repo.createDraft(
        fundId: 'f1', items: [partial('r1', 0, 'x')], createdByUid: 'inc');
    expect(zero.failureOrNull, isA<ValidationFailure>());
  });

  test('createDraft: partial requires remarks', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1', items: [partial('r1', 100000, '')], createdByUid: 'inc');
    expect(res.failureOrNull, isA<ValidationFailure>());
  });

  test('submit: a partial credits the fund, keeps the request released, writes a partial record', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final draft = (await repo.createDraft(
            fundId: 'f1',
            items: [partial('r1', 100000, 'first installment')],
            createdByUid: 'inc'))
        .valueOrNull!;
    final res = await repo.submit(replenishment: draft, actorUid: 'inc', notes: '');
    expect(res.isOk, isTrue);

    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 300000); // 200000 + 100000

    final r1 = await db.collection('requests').doc('r1').get();
    expect(r1.data()!['status'], 'released'); // stays released
    expect(r1.data()!['replenishedCentavos'], 100000);
    expect(r1.data()!['replenishmentId'], isNull);

    final partials = await db
        .collection('partialReplenishments')
        .where('requestId', isEqualTo: 'r1')
        .get();
    expect(partials.docs.length, 1);
    expect(partials.docs.single.data()['amountCentavos'], 100000);
    expect(partials.docs.single.data()['remarks'], 'first installment');
    expect(partials.docs.single.data()['replenishmentId'], draft.id);
  });

  test('submit rejects a stale draft that would over-replenish a request', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final draft = (await repo.createDraft(
            fundId: 'f1', items: [full('r1')], createdByUid: 'inc'))
        .valueOrNull!; // full item amount = 400000 (remaining at draft)
    // Simulate the request being partly replenished by some other path between
    // draft and submit: now remaining is only 300000, so applying the stale
    // 400000 would push replenishedCentavos (100000+400000) past amount (400000).
    await db.collection('requests').doc('r1').update({'replenishedCentavos': 100000});
    final res = await repo.submit(replenishment: draft, actorUid: 'inc', notes: '');
    expect(res.failureOrNull, isA<ValidationFailure>());
    // Fund untouched (the whole tx aborted).
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 200000);
  });

  test('createDraft accepts a partial of exactly remaining-1', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1', items: [partial('r1', 399999, 'almost')], createdByUid: 'inc');
    expect(res.isOk, isTrue);
    expect(res.valueOrNull!.items.single.amount.centavos, 399999);
  });

  test('installments: two partials then a full closes the request; fund fully restored', () async {
    // Fresh fund at full budget, one released request of 400000 (fund debited).
    db = FakeFirebaseFirestore();
    await db.collection('funds').doc('f1').set({
      'companyId': 'c1', 'name': 'PC',
      'originalBudgetCentavos': 10000000, 'availableBalanceCentavos': 9600000,
      'lowBalanceThresholdPct': 3, 'status': 'active',
    });
    await db.collection('requests').doc('r1').set({
      'companyId': 'c1', 'fundId': 'f1', 'createdByUid': 'inc',
      'beneficiaryName': 'B', 'amountCentavos': 400000, 'purpose': 'x',
      'proofImageUrl': 'http://img', 'status': 'released',
      'replenishmentId': null, 'replenishedCentavos': 0,
    });
    final repo = FirestoreReplenishmentRepository(db);

    Future<void> submitPartial(int c) async {
      final d = (await repo.createDraft(
              fundId: 'f1', items: [partial('r1', c, 'inst')], createdByUid: 'inc'))
          .valueOrNull!;
      // submit auto-approves: it credits the fund directly.
      expect((await repo.submit(replenishment: d, actorUid: 'inc', notes: ''))
          .isOk, isTrue);
    }

    await submitPartial(100000); // remaining 300000
    await submitPartial(150000); // remaining 150000
    // Full on the remainder closes it.
    final d = (await repo.createDraft(
            fundId: 'f1', items: [full('r1')], createdByUid: 'inc'))
        .valueOrNull!;
    expect(d.items.single.amount.centavos, 150000); // remaining
    expect((await repo.submit(replenishment: d, actorUid: 'inc', notes: ''))
        .isOk, isTrue);

    final r1 = await db.collection('requests').doc('r1').get();
    expect(r1.data()!['status'], 'replenished');
    expect(r1.data()!['replenishedCentavos'], 400000);
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 10000000); // fully restored
    final partials = await db
        .collection('partialReplenishments')
        .where('requestId', isEqualTo: 'r1')
        .get();
    expect(partials.docs.length, 2);
  });
}
