import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreRequestRepository repo;

  // Explicit Timestamps (NOT serverTimestamp): the fake resolves
  // serverTimestamp lazily, which makes orderBy on createdAt unreliable.
  Future<void> seed(
    String id, {
    required String companyId,
    required String status,
    required DateTime createdAt,
  }) =>
      db.collection('requests').doc(id).set({
        'companyId': companyId,
        'fundId': 'f',
        'createdByUid': 'u',
        'beneficiaryName': 'B',
        'amountCentavos': 100,
        'purpose': 'x',
        'proofImageUrl': 'http://img',
        'status': status,
        'replenishmentId': null,
        'createdAt': Timestamp.fromDate(createdAt),
      });

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreRequestRepository(db);
  });

  test(
      'watchAcknowledgedWorklist returns only this company\'s acknowledged + '
      'readyForRelease, newest first, excluding everything else', () async {
    // Company A spread across the lifecycle.
    await seed('a-pending',
        companyId: 'cA', status: 'pendingAck', createdAt: DateTime(2026, 1, 1));
    await seed('a-ack',
        companyId: 'cA', status: 'acknowledged', createdAt: DateTime(2026, 1, 2));
    await seed('a-ready',
        companyId: 'cA', status: 'readyForRelease', createdAt: DateTime(2026, 1, 4));
    await seed('a-released',
        companyId: 'cA', status: 'released', createdAt: DateTime(2026, 1, 5));
    await seed('a-rejected',
        companyId: 'cA', status: 'rejected', createdAt: DateTime(2026, 1, 6));
    // Company B acknowledged doc must NOT leak in.
    await seed('b-ack',
        companyId: 'cB', status: 'acknowledged', createdAt: DateTime(2026, 1, 3));

    final list = await repo.watchAcknowledgedWorklist('cA').first;

    // Only cA's acknowledged + readyForRelease, newest (a-ready) first.
    expect(list.map((r) => r.id).toList(), ['a-ready', 'a-ack']);
    expect(
      list.every((r) =>
          r.status == RequestStatus.acknowledged ||
          r.status == RequestStatus.readyForRelease),
      isTrue,
    );
    expect(list.every((r) => r.companyId == 'cA'), isTrue);
  });
}
