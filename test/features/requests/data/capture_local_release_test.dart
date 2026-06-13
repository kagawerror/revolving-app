import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreRequestRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreRequestRepository(db);
  });

  FundRequest created(String id) => FundRequest(
        id: id,
        companyId: 'c1',
        fundId: 'f1',
        createdByUid: 'u1',
        beneficiaryName: 'Ben',
        amount: Money.fromPesos(250),
        purpose: 'Supplies',
        proofImageUrl: 'https://cdn/p.jpg',
        status: RequestStatus.created,
      );

  test(
      'captureLocalRelease flips to released/localPending, stamps clientReleaseId, '
      'writes a history event, and leaves the fund balance untouched', () async {
    // Seed a fund and a created request.
    await db.collection('funds').doc('f1').set({
      'companyId': 'c1',
      'name': 'Main',
      'availableBalanceCentavos': 100000,
      'status': 'active',
    });
    await db.collection('requests').doc('r1').set(created('r1').toCreateMap()
      ..['proofImageUrl'] = 'https://cdn/p.jpg'
      ..['status'] = 'created');

    final res = await repo.captureLocalRelease(
      request: created('r1'),
      clientReleaseId: 'cli-123',
      actorUid: 'u1',
    );
    expect(res.isOk, isTrue);
    // Let the (unawaited) plain writes flush against the in-memory fake.
    await Future<void>.delayed(Duration.zero);

    final doc = await db.collection('requests').doc('r1').get();
    final data = doc.data()!;
    expect(data['status'], 'released');
    expect(data['releaseState'], 'localPending');
    expect(data['clientReleaseId'], 'cli-123');
    expect(data['releaseProofUrl'], '');
    expect(data['releaseSignatureUrl'], '');
    expect(data['pendingImageRef'], 'cli-123');

    // Fund balance MUST be untouched — only the server transaction debits it.
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 100000);

    // History event recorded for the offline capture.
    final history = await db
        .collection('requests')
        .doc('r1')
        .collection('history')
        .where('event', isEqualTo: 'released')
        .get();
    expect(history.docs, isNotEmpty);
    final ev = history.docs.first.data();
    expect(ev['to'], 'released');
    expect(ev['from'], 'created');
    expect(ev['clientReleaseId'], 'cli-123');
    expect(ev['releaseState'], 'localPending');
  });

  test('captureLocalRelease rejects a request not in a releasable state',
      () async {
    final res = await repo.captureLocalRelease(
      request: created('r1').copyWith(status: RequestStatus.released),
      clientReleaseId: 'cli-1',
      actorUid: 'u1',
    );
    expect(res.failureOrNull, isA<ValidationFailure>());
  });
}
