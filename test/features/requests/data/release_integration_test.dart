import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';

void main() {
  group('release transaction against fake Firestore', () {
    test('releases: deducts balance, flips fund to low, marks request released,'
        ' writes history', () async {
      final fake = FakeFirebaseFirestore();

      await fake.collection('funds').doc('f1').set(<String, dynamic>{
        'companyId': 'c1',
        'name': 'PC',
        'originalBudgetCentavos': 10000000, // ₱100,000
        'availableBalanceCentavos': 500000, // ₱5,000
        'lowBalanceThresholdPct': 3,
        'status': 'active',
      });

      final requestMap = <String, dynamic>{
        'companyId': 'c1',
        'fundId': 'f1',
        'createdByUid': 'u1',
        'beneficiaryName': 'Ben',
        'amountCentavos': 200000, // ₱2,000
        'purpose': 'x',
        'proofImageUrl': 'https://img/x.jpg',
        'status': 'readyForRelease',
      };
      await fake.collection('requests').doc('r1').set(requestMap);

      final req = FundRequest.fromMap('r1', requestMap);

      final result = await FirestoreRequestRepository(fake)
          .release(request: req, actorUid: 'incharge1');

      expect(result.isOk, isTrue);
      expect(result.failureOrNull, isNull);

      // Fund: balance deducted (5,000 - 2,000 = 3,000) and flipped to low
      // because 3,000 == 3% of 100,000 (boundary <=).
      final fundAfter =
          (await fake.collection('funds').doc('f1').get()).data()!;
      expect(fundAfter['availableBalanceCentavos'], 300000);
      expect(fundAfter['status'], 'low');

      // Request: now released.
      final reqAfter =
          (await fake.collection('requests').doc('r1').get()).data()!;
      expect(reqAfter['status'], 'released');

      // History: at least one 'released' doc.
      final history = await fake
          .collection('requests')
          .doc('r1')
          .collection('history')
          .get();
      final released = history.docs
          .map((d) => d.data())
          .where((m) => m['event'] == 'released' && m['to'] == 'released')
          .toList();
      expect(released, isNotEmpty);
    });

    test('insufficient balance: fails with ValidationFailure and rolls back',
        () async {
      final fake = FakeFirebaseFirestore();

      await fake.collection('funds').doc('f1').set(<String, dynamic>{
        'companyId': 'c1',
        'name': 'PC',
        'originalBudgetCentavos': 10000000, // ₱100,000
        'availableBalanceCentavos': 100000, // ₱1,000
        'lowBalanceThresholdPct': 3,
        'status': 'active',
      });

      final requestMap = <String, dynamic>{
        'companyId': 'c1',
        'fundId': 'f1',
        'createdByUid': 'u1',
        'beneficiaryName': 'Ben',
        'amountCentavos': 200000, // ₱2,000 > ₱1,000 available
        'purpose': 'x',
        'proofImageUrl': 'https://img/x.jpg',
        'status': 'readyForRelease',
      };
      await fake.collection('requests').doc('r1').set(requestMap);

      final req = FundRequest.fromMap('r1', requestMap);

      final result = await FirestoreRequestRepository(fake)
          .release(request: req, actorUid: 'incharge1');

      expect(result.failureOrNull, isA<ValidationFailure>());

      // Nothing applied: balance unchanged, request still ready.
      final fundAfter =
          (await fake.collection('funds').doc('f1').get()).data()!;
      expect(fundAfter['availableBalanceCentavos'], 100000);

      final reqAfter =
          (await fake.collection('requests').doc('r1').get()).data()!;
      expect(reqAfter['status'], 'readyForRelease');
    });
  });
}
