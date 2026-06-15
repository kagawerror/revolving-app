import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/sync/domain/release_sync_result.dart';

/// Part 3 — request-lifecycle notification denormalization. All against
/// FakeFirebaseFirestore. Each test asserts the notification doc carries the
/// right type/roles/requestId/amount/names, and that money fields are untouched
/// by the notification addition.
void main() {
  late FakeFirebaseFirestore fake;
  late FirestoreRequestRepository repo;

  Future<void> seedFund({int balance = 500000, String status = 'active'}) =>
      fake.collection('funds').doc('f1').set(<String, dynamic>{
        'companyId': 'c1',
        'name': 'Petty Cash',
        'originalBudgetCentavos': 10000000,
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
    String releaseState = '',
  }) async {
    final map = <String, dynamic>{
      'companyId': 'c1',
      'fundId': 'f1',
      'createdByUid': 'u1',
      'beneficiaryName': 'Ben',
      'amountCentavos': amountCentavos,
      'purpose': 'Office supplies',
      'proofImageUrl': 'https://img/x.jpg',
      'status': status,
      'releaseProofUrl': releaseProofUrl,
      'releaseSignatureUrl': releaseSignatureUrl,
      'clientReleaseId': clientReleaseId,
      if (releaseState.isNotEmpty) 'releaseState': releaseState,
    };
    await fake.collection('requests').doc('r1').set(map);
    return FundRequest.fromMap('r1', map);
  }

  Future<List<Map<String, dynamic>>> notifsOfType(String type) async => (await fake
          .collection('notifications')
          .where('type', isEqualTo: type)
          .get())
      .docs
      .map((d) => d.data())
      .toList();

  Future<int> fundBalance() async =>
      (await fake.collection('funds').doc('f1').get())
          .data()!['availableBalanceCentavos'] as int;

  setUp(() {
    fake = FakeFirebaseFirestore();
    repo = FirestoreRequestRepository(fake);
  });

  group('getById', () {
    test('existing → Ok with the request', () async {
      await seedFund();
      await seedRequest('released');
      final res = await repo.getById('r1');
      expect(res.isOk, isTrue);
      expect(res.valueOrNull!.id, 'r1');
    });

    test('missing → NotFoundFailure', () async {
      final res = await repo.getById('nope');
      expect(res.failureOrNull, isA<NotFoundFailure>());
    });
  });

  group('requestReleased (online _runRelease)', () {
    test('stages a requestReleased notification with denormalized fields',
        () async {
      await seedFund(balance: 500000);
      final req = await seedRequest('created',
          releaseProofUrl: '', releaseSignatureUrl: '');

      final res = await repo.release(
        request: req,
        actorUid: 'inc1',
        releaseProofUrl: 'https://img/release.jpg',
        releaseSignatureUrl: 'https://img/sig.png',
        clientReleaseId: 'cid-1',
      );
      expect(res.isOk, isTrue);

      final notifs = await notifsOfType('requestReleased');
      // EXACTLY ONCE per release.
      expect(notifs, hasLength(1));
      final n = notifs.first;
      expect((n['recipientRoles'] as List), ['superior', 'manager', 'ceo']);
      expect(n['requestId'], 'r1');
      expect(n['requestAmountCentavos'], 200000);
      expect(n['requestBeneficiaryName'], 'Ben');
      expect(n['requestPurpose'], 'Office supplies');
      expect(n['fundName'], 'Petty Cash');
      // No money snapshot leaks into the body.
      expect(n['body'], 'A cash release needs your review.');
      // Money still moved correctly (5,000 - 2,000 = 3,000).
      expect(await fundBalance(), 300000);
    });
  });

  group('requestAcknowledged', () {
    test('stages incharge notification with actor + fund name; no balance move',
        () async {
      await seedFund();
      final req = await seedRequest('released');

      final res = await repo.acknowledgePostRelease(
        request: req,
        actorUid: 'app1',
        actorName: 'Approver Ann',
        fundName: 'Petty Cash',
      );
      expect(res.isOk, isTrue);

      final notifs = await notifsOfType('requestAcknowledged');
      expect(notifs, hasLength(1));
      final n = notifs.first;
      expect((n['recipientRoles'] as List), ['incharge']);
      expect(n['requestId'], 'r1');
      expect(n['requestAmountCentavos'], 200000);
      expect(n['requestBeneficiaryName'], 'Ben');
      expect(n['actorName'], 'Approver Ann');
      expect(n['fundName'], 'Petty Cash');
      expect(await fundBalance(), 500000);
    });
  });

  group('requestDisputed', () {
    test('stages incharge notification but NEVER carries the dispute reason',
        () async {
      await seedFund();
      final req = await seedRequest('released');

      final res = await repo.dispute(
        request: req,
        actorUid: 'app1',
        reason: 'secret amount mismatch detail',
        actorName: 'Approver Ann',
        fundName: 'Petty Cash',
      );
      expect(res.isOk, isTrue);

      final notifs = await notifsOfType('requestDisputed');
      expect(notifs, hasLength(1));
      final n = notifs.first;
      expect((n['recipientRoles'] as List), ['incharge']);
      expect(n['requestId'], 'r1');
      expect(n['actorName'], 'Approver Ann');
      expect(n['fundName'], 'Petty Cash');
      // PII guard: neither the body nor any field carries the reason.
      expect(n['body'], 'A cash release was disputed.');
      expect(n.values.contains('secret amount mismatch detail'), isFalse);
      expect(await fundBalance(), 500000);
    });
  });

  group('requestRejected (conflict → rejected)', () {
    test('stages incharge notification; no money moved', () async {
      await seedFund();
      final req = await seedRequest('conflict');

      final res = await repo.resolveConflict(
        request: req,
        to: RequestStatus.rejected,
        actorUid: 'inc1',
        fundName: 'Petty Cash',
      );
      expect(res.isOk, isTrue);

      final notifs = await notifsOfType('requestRejected');
      expect(notifs, hasLength(1));
      final n = notifs.first;
      expect((n['recipientRoles'] as List), ['incharge']);
      expect(n['requestId'], 'r1');
      expect(n['requestAmountCentavos'], 200000);
      expect(n['requestBeneficiaryName'], 'Ben');
      expect(n['fundName'], 'Petty Cash');
      expect(await fundBalance(), 500000);
    });
  });

  group('offline confirm fires requestReleased exactly once', () {
    test('confirmPendingRelease (applied) stages one requestReleased', () async {
      await seedFund(balance: 500000);
      // A locally-captured offline release: released + localPending, empty URLs.
      final req = await seedRequest(
        'released',
        releaseProofUrl: '',
        releaseSignatureUrl: '',
        clientReleaseId: 'cid-offline',
        releaseState: 'localPending',
      );

      final res = await repo.confirmPendingRelease(
        request: req,
        clientReleaseId: 'cid-offline',
        releaseProofUrl: 'https://img/release.jpg',
        releaseSignatureUrl: 'https://img/sig.png',
        actorUid: 'inc1',
      );
      expect(res.valueOrNull, ReleaseSyncResult.confirmed);

      final notifs = await notifsOfType('requestReleased');
      expect(notifs, hasLength(1));
      expect(await fundBalance(), 300000);
    });
  });
}
