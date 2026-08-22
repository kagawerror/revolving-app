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

  test('watchByStatusAll returns pending docs across all companies, excluding other statuses',
      () async {
    await seed('a', companyId: 'c1', status: 'created', createdAt: DateTime(2026, 1, 1));
    await seed('b', companyId: 'c2', status: 'created', createdAt: DateTime(2026, 1, 2));
    await seed('c', companyId: 'c1', status: 'acknowledged', createdAt: DateTime(2026, 1, 3));
    await seed('d', companyId: 'c2', status: 'released', createdAt: DateTime(2026, 1, 4));

    final list = await repo.watchByStatusAll(RequestStatus.created).first;
    final ids = list.map((r) => r.id).toSet();
    expect(ids, {'a', 'b'});
    expect(list.every((r) => r.status == RequestStatus.created), isTrue);
  });

  test('watchRecentAll returns the N newest across companies in createdAt-desc order',
      () async {
    await seed('old', companyId: 'c1', status: 'released', createdAt: DateTime(2026, 1, 1));
    await seed('mid', companyId: 'c2', status: 'pendingAck', createdAt: DateTime(2026, 1, 2));
    await seed('new', companyId: 'c1', status: 'acknowledged', createdAt: DateTime(2026, 1, 3));

    final list = await repo.watchRecentAll(2).first;
    expect(list.map((r) => r.id).toList(), ['new', 'mid']);
  });
}
