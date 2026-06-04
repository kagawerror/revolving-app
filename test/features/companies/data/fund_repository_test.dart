import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/data/firestore_fund_repository.dart';

void main() {
  late FakeFirebaseFirestore db;

  Future<void> seedFund({
    int budget = 10000000,
    int balance = 5000000,
    String status = 'active',
  }) =>
      db.collection('funds').doc('f1').set({
        'companyId': 'c1',
        'name': 'Petty Cash',
        'originalBudgetCentavos': budget,
        'availableBalanceCentavos': balance,
        'lowBalanceThresholdPct': 3,
        'status': status,
      });

  setUp(() => db = FakeFirebaseFirestore());

  group('updateDetails', () {
    test('updates name and threshold only, leaves money fields untouched',
        () async {
      await seedFund();
      final repo = FirestoreFundRepository(db);
      final res = await repo.updateDetails(
        fundId: 'f1',
        name: 'Renamed',
        lowBalanceThresholdPct: 10,
      );
      expect(res.isOk, isTrue);
      final data = (await db.collection('funds').doc('f1').get()).data()!;
      expect(data['name'], 'Renamed');
      expect(data['lowBalanceThresholdPct'], 10);
      expect(data['originalBudgetCentavos'], 10000000);
      expect(data['availableBalanceCentavos'], 5000000);
    });
  });

  group('adjustBudget', () {
    test('increase applies delta to balance and writes a history entry',
        () async {
      await seedFund(budget: 10000000, balance: 5000000);
      final repo = FirestoreFundRepository(db);
      final res = await repo.adjustBudget(
        fundId: 'f1',
        newBudget: Money.fromCentavos(12000000),
        actorUid: 'admin-1',
        note: 'Admin budget edit',
      );
      expect(res.isOk, isTrue);
      final data = (await db.collection('funds').doc('f1').get()).data()!;
      expect(data['originalBudgetCentavos'], 12000000);
      expect(data['availableBalanceCentavos'], 7000000);
      expect(data['status'], 'active');

      final history =
          await db.collection('funds').doc('f1').collection('history').get();
      expect(history.docs.length, 1);
      final h = history.docs.first.data();
      expect(h['event'], 'budgetAdjusted');
      expect(h['actorUid'], 'admin-1');
      expect(h['deltaCentavos'], 2000000);
      expect(h['toBalanceCentavos'], 7000000);
      expect(h['note'], 'Admin budget edit');
    });

    test('decrease that crosses into low flips status', () async {
      // threshold 3% of new budget 10,000,000 = 300,000; new balance 200,000.
      await seedFund(budget: 10800000, balance: 1000000, status: 'active');
      final repo = FirestoreFundRepository(db);
      final res = await repo.adjustBudget(
        fundId: 'f1',
        newBudget: Money.fromCentavos(10000000),
        actorUid: 'admin-1',
        note: '',
      );
      expect(res.isOk, isTrue);
      final data = (await db.collection('funds').doc('f1').get()).data()!;
      expect(data['availableBalanceCentavos'], 200000);
      expect(data['status'], 'low');
    });

    test('decrease exceeding available balance returns ValidationFailure and writes nothing',
        () async {
      await seedFund(budget: 10000000, balance: 5000000);
      final repo = FirestoreFundRepository(db);
      final res = await repo.adjustBudget(
        fundId: 'f1',
        newBudget: Money.fromCentavos(4000000), // -60k vs 50k balance
        actorUid: 'admin-1',
        note: '',
      );
      expect(res.failureOrNull, isA<ValidationFailure>());
      final data = (await db.collection('funds').doc('f1').get()).data()!;
      expect(data['originalBudgetCentavos'], 10000000); // unchanged
      expect(data['availableBalanceCentavos'], 5000000);
      final history =
          await db.collection('funds').doc('f1').collection('history').get();
      expect(history.docs, isEmpty);
    });

    test('missing fund returns ValidationFailure', () async {
      final repo = FirestoreFundRepository(db);
      final res = await repo.adjustBudget(
        fundId: 'nope',
        newBudget: Money.fromCentavos(12000000),
        actorUid: 'admin-1',
        note: '',
      );
      expect(res.failureOrNull, isA<ValidationFailure>());
    });
  });
}
