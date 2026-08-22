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
      'watchAcknowledgedWorklist (release-first) returns only this company\'s '
      'created requests awaiting release, newest first', () async {
    // Company A spread across the release-first lifecycle.
    await seed('a-created-old',
        companyId: 'cA', status: 'created', createdAt: DateTime(2026, 1, 1));
    await seed('a-created-new',
        companyId: 'cA', status: 'created', createdAt: DateTime(2026, 1, 4));
    await seed('a-released',
        companyId: 'cA', status: 'released', createdAt: DateTime(2026, 1, 5));
    await seed('a-rejected',
        companyId: 'cA', status: 'rejected', createdAt: DateTime(2026, 1, 6));
    // Company B created doc must NOT leak in.
    await seed('b-created',
        companyId: 'cB', status: 'created', createdAt: DateTime(2026, 1, 3));

    final list = await repo.watchAcknowledgedWorklist('cA').first;

    // Only cA's created requests, newest (a-created-new) first.
    expect(list.map((r) => r.id).toList(), ['a-created-new', 'a-created-old']);
    expect(list.every((r) => r.status == RequestStatus.created), isTrue);
    expect(list.every((r) => r.companyId == 'cA'), isTrue);
  });

  test('watchConflicts / watchPostReleaseReview / watchDisputed filter by '
      'their single status', () async {
    await seed('c1',
        companyId: 'cA', status: 'conflict', createdAt: DateTime(2026, 2, 1));
    await seed('r1',
        companyId: 'cA', status: 'released', createdAt: DateTime(2026, 2, 2));
    await seed('d1',
        companyId: 'cA', status: 'disputed', createdAt: DateTime(2026, 2, 3));

    expect((await repo.watchConflicts('cA').first).map((r) => r.id), ['c1']);
    expect((await repo.watchPostReleaseReview('cA').first).map((r) => r.id), ['r1']);
    expect((await repo.watchDisputed('cA').first).map((r) => r.id), ['d1']);
  });
}
