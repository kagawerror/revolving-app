import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/sync/domain/release_sync_result.dart';

/// Tests for the offline-release REPLAY money step: confirmPendingRelease.
/// The request doc is its own idempotency ledger (releaseState localPending →
/// serverConfirmed), and the fund is debited EXACTLY ONCE, server-side.
void main() {
  late FakeFirebaseFirestore db;
  late FirestoreRequestRepository repo;

  const companyId = 'c1';
  const fundId = 'f1';

  Future<void> seedFund({required int balanceCentavos, int budget = 1000000}) =>
      db.collection('funds').doc(fundId).set({
        'companyId': companyId,
        'name': 'Petty',
        'originalBudgetCentavos': budget,
        'availableBalanceCentavos': balanceCentavos,
        'lowBalanceThresholdPct': 3,
        'status': 'active',
      });

  /// Seeds a captured offline release: status released, releaseState
  /// localPending, clientReleaseId stamped, empty URLs, pendingImageRef set.
  Future<FundRequest> seedLocalPending(
    String id, {
    required int amountCentavos,
    required String clientReleaseId,
  }) async {
    await db.collection('requests').doc(id).set({
      'companyId': companyId,
      'fundId': fundId,
      'createdByUid': 'u-incharge',
      'beneficiaryName': 'B',
      'amountCentavos': amountCentavos,
      'purpose': 'x',
      'proofImageUrl': 'http://proof',
      'status': RequestStatus.released.name,
      'releaseState': 'localPending',
      'clientReleaseId': clientReleaseId,
      'releaseProofUrl': '',
      'releaseSignatureUrl': '',
      'pendingImageRef': clientReleaseId,
      'replenishmentId': null,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
    final snap = await db.collection('requests').doc(id).get();
    return FundRequest.fromMap(id, snap.data()!);
  }

  Future<int> fundBalance() async {
    final snap = await db.collection('funds').doc(fundId).get();
    return snap.data()!['availableBalanceCentavos'] as int;
  }

  Future<Map<String, dynamic>> reqData(String id) async =>
      (await db.collection('requests').doc(id).get()).data()!;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreRequestRepository(db);
  });

  test('localPending → confirmed debits the fund exactly once + backfills',
      () async {
    await seedFund(balanceCentavos: 100000);
    final req =
        await seedLocalPending('r1', amountCentavos: 30000, clientReleaseId: 'crid-1');

    final res = await repo.confirmPendingRelease(
      request: req,
      clientReleaseId: 'crid-1',
      releaseProofUrl: 'http://rel-proof',
      releaseSignatureUrl: 'http://rel-sig',
      actorUid: 'u-incharge',
    );

    expect(res, isA<Ok<ReleaseSyncResult>>());
    expect(res.valueOrNull, ReleaseSyncResult.confirmed);
    expect(await fundBalance(), 100000 - 30000);

    final d = await reqData('r1');
    expect(d['releaseState'], 'serverConfirmed');
    expect(d['releaseProofUrl'], 'http://rel-proof');
    expect(d['releaseSignatureUrl'], 'http://rel-sig');
    expect(d['status'], RequestStatus.released.name);
    // pendingImageRef cleared.
    expect(d['pendingImageRef'], anyOf(isNull, ''));

    // History event carries the clientReleaseId.
    final history = await db
        .collection('requests')
        .doc('r1')
        .collection('history')
        .get();
    final confirmEvents =
        history.docs.where((h) => h.data()['clientReleaseId'] == 'crid-1');
    expect(confirmEvents, isNotEmpty);
  });

  test('idempotency: calling confirmPendingRelease TWICE debits only once',
      () async {
    await seedFund(balanceCentavos: 100000);
    final req =
        await seedLocalPending('r1', amountCentavos: 30000, clientReleaseId: 'crid-1');

    final first = await repo.confirmPendingRelease(
      request: req,
      clientReleaseId: 'crid-1',
      releaseProofUrl: 'http://rel-proof',
      releaseSignatureUrl: 'http://rel-sig',
      actorUid: 'u-incharge',
    );
    expect(first.valueOrNull, ReleaseSyncResult.confirmed);
    expect(await fundBalance(), 70000);

    // Re-read the (now serverConfirmed) request and replay again.
    final after = FundRequest.fromMap('r1', await reqData('r1'));
    final second = await repo.confirmPendingRelease(
      request: after,
      clientReleaseId: 'crid-1',
      releaseProofUrl: 'http://rel-proof',
      releaseSignatureUrl: 'http://rel-sig',
      actorUid: 'u-incharge',
    );

    expect(second.valueOrNull, ReleaseSyncResult.alreadyConfirmed);
    // Balance UNCHANGED — no second debit.
    expect(await fundBalance(), 70000);
  });

  test('overdraft / cross-device: two captured 80 releases against balance 100 '
      '→ first confirms, second conflicts; fund never goes negative', () async {
    await seedFund(balanceCentavos: 100);
    final r1 =
        await seedLocalPending('r1', amountCentavos: 80, clientReleaseId: 'crid-1');
    final r2 =
        await seedLocalPending('r2', amountCentavos: 80, clientReleaseId: 'crid-2');

    final first = await repo.confirmPendingRelease(
      request: r1,
      clientReleaseId: 'crid-1',
      releaseProofUrl: 'http://p1',
      releaseSignatureUrl: 'http://s1',
      actorUid: 'u',
    );
    expect(first.valueOrNull, ReleaseSyncResult.confirmed);
    expect(await fundBalance(), 20);

    final second = await repo.confirmPendingRelease(
      request: r2,
      clientReleaseId: 'crid-2',
      releaseProofUrl: 'http://p2',
      releaseSignatureUrl: 'http://s2',
      actorUid: 'u',
    );
    expect(second.valueOrNull, ReleaseSyncResult.conflict);

    // Fund stays at 20 — NOT negative, NOT debited again.
    expect(await fundBalance(), 20);

    final d2 = await reqData('r2');
    expect(d2['status'], RequestStatus.conflict.name);
    expect(d2['releaseState'], 'conflict');

    // Conflict history event written with clientReleaseId + a reason.
    final history = await db
        .collection('requests')
        .doc('r2')
        .collection('history')
        .get();
    final conflictEvents = history.docs
        .where((h) => h.data()['to'] == RequestStatus.conflict.name);
    expect(conflictEvents, isNotEmpty);
    expect(conflictEvents.first.data()['clientReleaseId'], 'crid-2');
  });

  test('exactly-equal balance is NOT a conflict (boundary)', () async {
    await seedFund(balanceCentavos: 5000);
    final req =
        await seedLocalPending('r1', amountCentavos: 5000, clientReleaseId: 'crid-1');

    final res = await repo.confirmPendingRelease(
      request: req,
      clientReleaseId: 'crid-1',
      releaseProofUrl: 'http://p',
      releaseSignatureUrl: 'http://s',
      actorUid: 'u',
    );

    expect(res.valueOrNull, ReleaseSyncResult.confirmed);
    expect(await fundBalance(), 0);
  });

  test('already in conflict → returns conflict idempotently, no fund touch',
      () async {
    await seedFund(balanceCentavos: 100);
    await db.collection('requests').doc('r1').set({
      'companyId': companyId,
      'fundId': fundId,
      'createdByUid': 'u',
      'beneficiaryName': 'B',
      'amountCentavos': 80,
      'purpose': 'x',
      'proofImageUrl': 'http://proof',
      'status': RequestStatus.conflict.name,
      'releaseState': 'conflict',
      'clientReleaseId': 'crid-1',
      'releaseProofUrl': '',
      'releaseSignatureUrl': '',
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
    final req = FundRequest.fromMap('r1', await reqData('r1'));

    final res = await repo.confirmPendingRelease(
      request: req,
      clientReleaseId: 'crid-1',
      releaseProofUrl: 'http://p',
      releaseSignatureUrl: 'http://s',
      actorUid: 'u',
    );

    expect(res.valueOrNull, ReleaseSyncResult.conflict);
    expect(await fundBalance(), 100);
  });

  test('missing request → NotFound', () async {
    await seedFund(balanceCentavos: 100);
    final ghost = FundRequest(
      id: 'ghost',
      companyId: companyId,
      fundId: fundId,
      createdByUid: 'u',
      beneficiaryName: 'B',
      amount: Money.fromCentavos(10),
      purpose: 'x',
      proofImageUrl: 'http://proof',
      status: RequestStatus.released,
      clientReleaseId: 'crid-x',
      releaseState: 'localPending',
    );

    final res = await repo.confirmPendingRelease(
      request: ghost,
      clientReleaseId: 'crid-x',
      releaseProofUrl: 'http://p',
      releaseSignatureUrl: 'http://s',
      actorUid: 'u',
    );

    expect(res.isOk, isFalse);
  });

  test('newly-low fund flips status to low on confirm', () async {
    // budget 1,000,000; threshold 3% = 30,000. Release leaves 25,000 (< low).
    await seedFund(balanceCentavos: 55000);
    final req = await seedLocalPending('r1',
        amountCentavos: 30000, clientReleaseId: 'crid-1');

    final res = await repo.confirmPendingRelease(
      request: req,
      clientReleaseId: 'crid-1',
      releaseProofUrl: 'http://p',
      releaseSignatureUrl: 'http://s',
      actorUid: 'u',
    );

    expect(res.valueOrNull, ReleaseSyncResult.confirmed);
    final fund = (await db.collection('funds').doc(fundId).get()).data()!;
    expect(fund['status'], 'low');
  });

  group('backfillCreateImage', () {
    test('sets proofImageUrl and clears pendingImageRef', () async {
      await db.collection('requests').doc('r1').set({
        'companyId': companyId,
        'fundId': fundId,
        'createdByUid': 'u',
        'beneficiaryName': 'B',
        'amountCentavos': 100,
        'purpose': 'x',
        'proofImageUrl': '',
        'status': RequestStatus.created.name,
        'pendingImageRef': 'pending-1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });

      final res = await repo.backfillCreateImage(
        requestId: 'r1',
        proofImageUrl: 'http://uploaded',
      );
      expect(res.isOk, isTrue);

      final d = await reqData('r1');
      expect(d['proofImageUrl'], 'http://uploaded');
      expect(d['pendingImageRef'], anyOf(isNull, ''));
      // amount untouched.
      expect(d['amountCentavos'], 100);
    });
  });
}
