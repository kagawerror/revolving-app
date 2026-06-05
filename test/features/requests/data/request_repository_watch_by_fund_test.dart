import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';

/// `watchByFund` must constrain the query by BOTH `companyId` and `fundId`.
///
/// The requests read rule is `sameCompany(resource.data.companyId)`, and
/// Firestore rejects any list query it cannot prove is company-scoped
/// ("rules are not filters"). A query filtered on `fundId` alone is rejected
/// with permission-denied on the device even though it passes here, because
/// the fake doesn't enforce rules. These tests pin the company scoping so the
/// equality filter can't silently regress.
void main() {
  late FakeFirebaseFirestore db;
  late FirestoreRequestRepository repo;

  Future<void> seed(
    String id, {
    required String companyId,
    required String fundId,
  }) =>
      db.collection('requests').doc(id).set({
        'companyId': companyId,
        'fundId': fundId,
        'createdByUid': 'u',
        'beneficiaryName': 'B',
        'amountCentavos': 100,
        'purpose': 'x',
        'proofImageUrl': 'http://img',
        'status': 'pendingAck',
        'replenishmentId': null,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreRequestRepository(db);
  });

  test('returns only requests for the given fund within the given company',
      () async {
    await seed('a', companyId: 'c1', fundId: 'f1');
    await seed('b', companyId: 'c1', fundId: 'f1');
    await seed('other-fund', companyId: 'c1', fundId: 'f2');

    final list = await repo.watchByFund('c1', 'f1').first;
    expect(list.map((r) => r.id).toSet(), {'a', 'b'});
  });

  test('excludes a foreign company that happens to share the fundId', () async {
    await seed('mine', companyId: 'c1', fundId: 'f1');
    await seed('foreign', companyId: 'c2', fundId: 'f1');

    final list = await repo.watchByFund('c1', 'f1').first;
    expect(list.map((r) => r.id).toSet(), {'mine'});
  });
}
