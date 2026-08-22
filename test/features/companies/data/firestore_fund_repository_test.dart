import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/companies/data/firestore_fund_repository.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    Future<void> seed(String id, String companyId, String name) =>
        db.collection('funds').doc(id).set({
          'companyId': companyId,
          'name': name,
          'originalBudgetCentavos': 10000000,
          'availableBalanceCentavos': 500000,
          'lowBalanceThresholdPct': 3,
          'status': 'active',
        });
    await seed('f3', 'c2', 'Zeta');
    await seed('f1', 'c1', 'Alpha');
    await seed('f2', 'c1', 'Mid');
  });

  test('watchAll emits every fund across companies sorted by name', () async {
    final repo = FirestoreFundRepository(db);
    final funds = await repo.watchAll().first;

    expect(funds.map((f) => f.name).toList(), ['Alpha', 'Mid', 'Zeta']);
    expect(funds.map((f) => f.companyId).toList(), ['c1', 'c1', 'c2']);
  });

  test('watchByCompany scopes to one company', () async {
    final repo = FirestoreFundRepository(db);
    final funds = await repo.watchByCompany('c1').first;

    expect(funds.map((f) => f.name).toList(), ['Alpha', 'Mid']);
    expect(funds.every((f) => f.companyId == 'c1'), isTrue);
  });
}
