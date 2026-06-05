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

  test('one-tap release directly from acknowledged succeeds and deducts once',
      () async {
    final fake = FakeFirebaseFirestore();
    await seedFund(fake);
    await fake.collection('requests').doc('r1').set(requestMap('acknowledged'));
    final req = FundRequest.fromMap('r1', requestMap('acknowledged'));

    final res = await FirestoreRequestRepository(fake)
        .release(request: req, actorUid: 'incharge1');

    expect(res.isOk, isTrue);
    final fundAfter = (await fake.collection('funds').doc('f1').get()).data()!;
    expect(fundAfter['availableBalanceCentavos'], 300000); // 5,000 - 2,000
    final reqAfter = (await fake.collection('requests').doc('r1').get()).data()!;
    expect(reqAfter['status'], 'released');

    // History 'from' reflects the actual server status it transitioned out of.
    final history = await fake
        .collection('requests')
        .doc('r1')
        .collection('history')
        .get();
    final released = history.docs
        .map((d) => d.data())
        .firstWhere((m) => m['event'] == 'released');
    expect(released['from'], 'acknowledged');
  });

  test(
      'second release on an already-released request returns Err and the fund '
      'is deducted exactly once', () async {
    final fake = FakeFirebaseFirestore();
    await seedFund(fake);
    await fake.collection('requests').doc('r1').set(requestMap('acknowledged'));

    final repo = FirestoreRequestRepository(fake);
    // Both callers hold the same stale acknowledged snapshot (shared worklist).
    final req = FundRequest.fromMap('r1', requestMap('acknowledged'));

    final first = await repo.release(request: req, actorUid: 'incharge1');
    expect(first.isOk, isTrue);

    // Second tap on the SAME stale request object.
    final second = await repo.release(request: req, actorUid: 'incharge2');
    expect(second.failureOrNull, isA<ValidationFailure>());

    // The fund must have been deducted exactly once.
    final fundAfter = (await fake.collection('funds').doc('f1').get()).data()!;
    expect(fundAfter['availableBalanceCentavos'], 300000); // not 100,000
  });
}
