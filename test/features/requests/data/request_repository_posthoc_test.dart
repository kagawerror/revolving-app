import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

/// Data-layer tests for the post-release / conflict-resolution repo methods
/// (G2). All run against FakeFirebaseFirestore. Money paths assert the fund
/// balance moves (or doesn't) exactly as the lifecycle requires.
void main() {
  late FakeFirebaseFirestore fake;
  late FirestoreRequestRepository repo;

  Future<void> seedFund({int balance = 500000, String status = 'active'}) =>
      fake.collection('funds').doc('f1').set(<String, dynamic>{
        'companyId': 'c1',
        'name': 'PC',
        'originalBudgetCentavos': 10000000, // ₱100,000
        'availableBalanceCentavos': balance,
        'lowBalanceThresholdPct': 3,
        'status': status,
      });

  Future<FundRequest> seedRequest(
    String status, {
    int amountCentavos = 200000,
    String releaseProofUrl = 'https://img/release.jpg',
    String releaseSignatureUrl = 'https://img/sig.png',
    String? clientReleaseId,
  }) async {
    final map = <String, dynamic>{
      'companyId': 'c1',
      'fundId': 'f1',
      'createdByUid': 'u1',
      'beneficiaryName': 'Ben',
      'amountCentavos': amountCentavos,
      'purpose': 'x',
      'proofImageUrl': 'https://img/x.jpg',
      'status': status,
      'releaseProofUrl': releaseProofUrl,
      'releaseSignatureUrl': releaseSignatureUrl,
      'clientReleaseId': clientReleaseId,
    };
    await fake.collection('requests').doc('r1').set(map);
    return FundRequest.fromMap('r1', map);
  }

  Future<int> fundBalance() async =>
      (await fake.collection('funds').doc('f1').get())
          .data()!['availableBalanceCentavos'] as int;

  Future<List<Map<String, dynamic>>> history() async => (await fake
          .collection('requests')
          .doc('r1')
          .collection('history')
          .get())
      .docs
      .map((d) => d.data())
      .toList();

  setUp(() {
    fake = FakeFirebaseFirestore();
    repo = FirestoreRequestRepository(fake);
  });

  group('acknowledgePostRelease', () {
    test('moves released → acknowledged, writes history, changes NO balance',
        () async {
      await seedFund();
      final req = await seedRequest('released');

      final result =
          await repo.acknowledgePostRelease(request: req, actorUid: 'approver1');

      expect(result.isOk, isTrue);
      final after =
          (await fake.collection('requests').doc('r1').get()).data()!;
      expect(after['status'], 'acknowledged');
      expect(after['approverUid'], 'approver1');
      expect(after['approverDecisionAt'], isNotNull);
      // Balance untouched — acknowledge moves no money.
      expect(await fundBalance(), 500000);

      final ackEvents =
          (await history()).where((m) => m['to'] == 'acknowledged').toList();
      expect(ackEvents, hasLength(1));
      expect(ackEvents.first['from'], 'released');
      expect(ackEvents.first['actorUid'], 'approver1');
    });
  });

  group('dispute', () {
    test('moves released → disputed, stamps reason/by/at, history, NO balance',
        () async {
      await seedFund();
      final req = await seedRequest('released');

      final result = await repo.dispute(
        request: req,
        actorUid: 'approver1',
        reason: 'amount mismatch',
      );

      expect(result.isOk, isTrue);
      final after =
          (await fake.collection('requests').doc('r1').get()).data()!;
      expect(after['status'], 'disputed');
      expect(after['disputedReason'], 'amount mismatch');
      expect(after['disputedByUid'], 'approver1');
      expect(after['disputedAt'], isNotNull);
      expect(await fundBalance(), 500000);

      final dispEvents =
          (await history()).where((m) => m['to'] == 'disputed').toList();
      expect(dispEvents, hasLength(1));
      expect(dispEvents.first['from'], 'released');
    });

    test('moves acknowledged → disputed', () async {
      await seedFund();
      final req = await seedRequest('acknowledged');

      final result = await repo.dispute(
        request: req,
        actorUid: 'approver1',
        reason: 'late objection',
      );

      expect(result.isOk, isTrue);
      final after =
          (await fake.collection('requests').doc('r1').get()).data()!;
      expect(after['status'], 'disputed');
      expect(await fundBalance(), 500000);
    });
  });

  group('resolveConflict', () {
    test('to rejected: plain transition, history, NO money moved', () async {
      await seedFund();
      final req = await seedRequest('conflict');

      final result = await repo.resolveConflict(
        request: req,
        to: RequestStatus.rejected,
        actorUid: 'incharge1',
      );

      expect(result.isOk, isTrue);
      final after =
          (await fake.collection('requests').doc('r1').get()).data()!;
      expect(after['status'], 'rejected');
      expect(await fundBalance(), 500000);

      final rejEvents =
          (await history()).where((m) => m['to'] == 'rejected').toList();
      expect(rejEvents, hasLength(1));
      expect(rejEvents.first['from'], 'conflict');
    });

    test('to released: re-runs release, debits the fund exactly once', () async {
      await seedFund(balance: 500000);
      final req = await seedRequest(
        'conflict',
        amountCentavos: 200000,
        clientReleaseId: 'cid-original',
      );

      final result = await repo.resolveConflict(
        request: req,
        to: RequestStatus.released,
        actorUid: 'incharge1',
      );

      expect(result.isOk, isTrue);
      final after =
          (await fake.collection('requests').doc('r1').get()).data()!;
      expect(after['status'], 'released');
      // Debited exactly once: 5,000 - 2,000 = 3,000.
      expect(await fundBalance(), 300000);
      // The original clientReleaseId is reused (idempotent reconcile).
      expect(after['clientReleaseId'], 'cid-original');

      final relEvents =
          (await history()).where((m) => m['to'] == 'released').toList();
      expect(relEvents, hasLength(1));
      expect(relEvents.first['clientReleaseId'], 'cid-original');
    });

    test('to an illegal target returns a ValidationFailure', () async {
      await seedFund();
      final req = await seedRequest('conflict');

      final result = await repo.resolveConflict(
        request: req,
        to: RequestStatus.acknowledged,
        actorUid: 'incharge1',
      );

      expect(result.isOk, isFalse);
    });
  });

  group('release persists clientReleaseId', () {
    test('writes clientReleaseId onto the request doc AND the history event',
        () async {
      await seedFund();
      final req = await seedRequest('created',
          releaseProofUrl: '', releaseSignatureUrl: '');

      final result = await repo.release(
        request: req,
        actorUid: 'incharge1',
        releaseProofUrl: 'https://img/release.jpg',
        releaseSignatureUrl: 'https://img/sig.png',
        clientReleaseId: 'cid-release-42',
      );

      expect(result.isOk, isTrue);
      final after =
          (await fake.collection('requests').doc('r1').get()).data()!;
      expect(after['clientReleaseId'], 'cid-release-42');
      expect(after['releaseState'], 'serverConfirmed');

      final relEvents =
          (await history()).where((m) => m['to'] == 'released').toList();
      expect(relEvents, hasLength(1));
      expect(relEvents.first['clientReleaseId'], 'cid-release-42');
    });
  });
}
