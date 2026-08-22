import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';

void main() {
  Future<void> seedFund(FakeFirebaseFirestore fake) =>
      fake.collection('funds').doc('f1').set(<String, dynamic>{
        'companyId': 'c1',
        'name': 'PC',
        'originalBudgetCentavos': 10000000, // ₱100,000
        'availableBalanceCentavos': 500000, // ₱5,000
        'lowBalanceThresholdPct': 3,
        'status': 'active',
      });

  Map<String, dynamic> requestMap(String status) => <String, dynamic>{
        'companyId': 'c1',
        'fundId': 'f1',
        'createdByUid': 'u1',
        'beneficiaryName': 'Ben',
        'amountCentavos': 200000, // ₱2,000
        'purpose': 'x',
        'proofImageUrl': 'https://img/x.jpg',
        'status': status,
      };

  group('release with mandatory proof + signature', () {
    test('missing signature -> ValidationFailure and fund balance unchanged',
        () async {
      final fake = FakeFirebaseFirestore();
      await seedFund(fake);
      await fake
          .collection('requests')
          .doc('r1')
          .set(requestMap('created'));
      final req = FundRequest.fromMap('r1', requestMap('created'));

      final res = await FirestoreRequestRepository(fake).release(
        request: req,
        actorUid: 'incharge1',
        releaseProofUrl: 'https://img/release.jpg',
        releaseSignatureUrl: '', // missing
        clientReleaseId: 'cid-test',
      );

      expect(res.failureOrNull, isA<ValidationFailure>());

      // No deduction: balance untouched, request still ready.
      final fundAfter = (await fake.collection('funds').doc('f1').get()).data()!;
      expect(fundAfter['availableBalanceCentavos'], 500000);
      final reqAfter =
          (await fake.collection('requests').doc('r1').get()).data()!;
      expect(reqAfter['status'], 'created');
      expect(reqAfter.containsKey('releaseSignatureUrl'), isFalse);
    });

    test('missing proof -> ValidationFailure and fund balance unchanged',
        () async {
      final fake = FakeFirebaseFirestore();
      await seedFund(fake);
      await fake
          .collection('requests')
          .doc('r1')
          .set(requestMap('created'));
      final req = FundRequest.fromMap('r1', requestMap('created'));

      final res = await FirestoreRequestRepository(fake).release(
        request: req,
        actorUid: 'incharge1',
        releaseProofUrl: '', // missing
        releaseSignatureUrl: 'https://img/sig.png',
        clientReleaseId: 'cid-test',
      );

      expect(res.failureOrNull, isA<ValidationFailure>());
      final fundAfter = (await fake.collection('funds').doc('f1').get()).data()!;
      expect(fundAfter['availableBalanceCentavos'], 500000);
    });

    test('valid release persists both URLs on request doc and history',
        () async {
      final fake = FakeFirebaseFirestore();
      await seedFund(fake);
      await fake
          .collection('requests')
          .doc('r1')
          .set(requestMap('created'));
      final req = FundRequest.fromMap('r1', requestMap('created'));

      final res = await FirestoreRequestRepository(fake).release(
        request: req,
        actorUid: 'incharge1',
        releaseProofUrl: 'https://img/release.jpg',
        releaseSignatureUrl: 'https://img/sig.png',
        clientReleaseId: 'cid-test',
      );

      expect(res.isOk, isTrue);

      final reqAfter =
          (await fake.collection('requests').doc('r1').get()).data()!;
      expect(reqAfter['status'], 'released');
      expect(reqAfter['releaseProofUrl'], 'https://img/release.jpg');
      expect(reqAfter['releaseSignatureUrl'], 'https://img/sig.png');

      final history = await fake
          .collection('requests')
          .doc('r1')
          .collection('history')
          .get();
      final released = history.docs
          .map((d) => d.data())
          .firstWhere((m) => m['event'] == 'released');
      expect(released['releaseProofUrl'], 'https://img/release.jpg');
      expect(released['releaseSignatureUrl'], 'https://img/sig.png');
    });
  });
}
