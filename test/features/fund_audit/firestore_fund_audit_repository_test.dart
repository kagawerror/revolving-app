import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/fund_audit/data/firestore_fund_audit_repository.dart';
import 'package:rev_app/features/fund_audit/domain/denomination.dart';
import 'package:rev_app/features/fund_audit/domain/denomination_count.dart';
import 'package:rev_app/features/fund_audit/domain/fund_audit.dart';
import 'package:rev_app/features/fund_audit/domain/fund_audit_math.dart';

FundAudit _audit({int variance = 20000}) => FundAudit(
      id: '',
      companyId: 'c1',
      fundId: 'f1',
      fundName: 'Petty Cash',
      companyName: 'Acme',
      custodianUid: 'u1',
      custodianName: 'Cathy',
      effectiveBudget: Money.fromCentavos(100000),
      physicalCash: Money.fromCentavos(50000),
      outstanding: Money.fromCentavos(30000),
      varianceCentavos: variance,
      denominations: const [
        DenominationCount(denomination: Denomination.p100, count: 5),
        DenominationCount(denomination: Denomination.c01, count: 0),
      ],
      proofImageUrl: 'https://cdn/proof.jpg',
      note: 'monthly count',
    );

void main() {
  group('FirestoreFundAuditRepository', () {
    test('create writes *Centavos, signed variance, and denominations array',
        () async {
      final fake = FakeFirebaseFirestore();
      final repo = FirestoreFundAuditRepository(fake);

      final result = await repo.create(_audit(variance: 20000));
      expect(result.isOk, isTrue);

      final id = result.valueOrNull!;
      final data = (await fake.collection('fundAudits').doc(id).get()).data()!;
      expect(data['companyId'], 'c1');
      expect(data['fundId'], 'f1');
      expect(data['effectiveBudgetCentavos'], 100000);
      expect(data['physicalCashCentavos'], 50000);
      expect(data['outstandingCentavos'], 30000);
      expect(data['varianceCentavos'], 20000);
      expect(data['custodianUid'], 'u1');
      final denoms = data['denominations'] as List;
      expect(denoms, hasLength(2));
      expect(denoms.first['denomination'], 'p100');
      expect(denoms.first['count'], 5);
    });

    test('create preserves a negative (overage) variance', () async {
      final fake = FakeFirebaseFirestore();
      final repo = FirestoreFundAuditRepository(fake);
      final id = (await repo.create(_audit(variance: -30000))).valueOrNull!;
      final data = (await fake.collection('fundAudits').doc(id).get()).data()!;
      expect(data['varianceCentavos'], -30000);
    });

    test(
        'fetchOutstandingForFund returns released/acknowledged/disputed for the '
        'fund and nets partial replenishment via remaining', () async {
      final fake = FakeFirebaseFirestore();
      // Release-first: released, acknowledged AND disputed are all still
      // outstanding (unreplenished released cash).
      await fake.collection('requests').add({
        'companyId': 'c1',
        'fundId': 'f1',
        'amountCentavos': 10000,
        'status': 'released',
        'proofImageUrl': 'x',
      });
      await fake.collection('requests').add({
        'companyId': 'c1',
        'fundId': 'f1',
        'amountCentavos': 7000,
        'status': 'acknowledged',
        'proofImageUrl': 'x',
      });
      await fake.collection('requests').add({
        'companyId': 'c1',
        'fundId': 'f1',
        'amountCentavos': 4000,
        'status': 'disputed',
        'proofImageUrl': 'x',
      });
      // Partially replenished but still outstanding: remaining = 8000 - 3000.
      await fake.collection('requests').add({
        'companyId': 'c1',
        'fundId': 'f1',
        'amountCentavos': 8000,
        'replenishedCentavos': 3000,
        'status': 'released',
        'proofImageUrl': 'x',
      });
      // Fully replenished — not outstanding.
      await fake.collection('requests').add({
        'companyId': 'c1',
        'fundId': 'f1',
        'amountCentavos': 5000,
        'status': 'replenished',
        'proofImageUrl': 'x',
      });
      // Not-yet-released lifecycle states do not count.
      await fake.collection('requests').add({
        'companyId': 'c1',
        'fundId': 'f1',
        'amountCentavos': 6000,
        'status': 'created',
        'proofImageUrl': 'x',
      });
      await fake.collection('requests').add({
        'companyId': 'c1',
        'fundId': 'f1',
        'amountCentavos': 6500,
        'status': 'rejected',
        'proofImageUrl': 'x',
      });
      // Outstanding but a different fund — excluded by the fundId filter.
      await fake.collection('requests').add({
        'companyId': 'c1',
        'fundId': 'f2',
        'amountCentavos': 9999,
        'status': 'released',
        'proofImageUrl': 'x',
      });

      final repo = FirestoreFundAuditRepository(fake);
      final res = await repo.fetchOutstandingForFund('c1', 'f1');
      expect(res.isOk, isTrue);
      final reqs = res.valueOrNull!;
      // released + acknowledged + disputed + partially-replenished released.
      expect(reqs, hasLength(4));
      // Outstanding sums each request's remaining (amount - replenished):
      // 10000 + 7000 + 4000 + (8000 - 3000) = 26000.
      expect(outstandingReleasedCash(reqs).centavos, 26000);
    });

    test('watchByFund streams newest-first', () async {
      final fake = FakeFirebaseFirestore();
      final repo = FirestoreFundAuditRepository(fake);
      await fake.collection('fundAudits').add({
        ..._audit().toCreateMap(),
        'createdAt': DateTime(2026, 1, 1),
        'note': 'older',
      });
      await fake.collection('fundAudits').add({
        ..._audit().toCreateMap(),
        'createdAt': DateTime(2026, 6, 1),
        'note': 'newer',
      });

      final list = await repo.watchByFund('c1', 'f1').first;
      expect(list, hasLength(2));
      expect(list.first.note, 'newer');
      expect(list.last.note, 'older');
    });

    test('getById returns NotFound for a missing doc', () async {
      final fake = FakeFirebaseFirestore();
      final repo = FirestoreFundAuditRepository(fake);
      final res = await repo.getById('nope');
      expect(res.isOk, isFalse);
      expect(res.failureOrNull, isNotNull);
    });

    test('getById round-trips a saved audit', () async {
      final fake = FakeFirebaseFirestore();
      final repo = FirestoreFundAuditRepository(fake);
      final id = (await repo.create(_audit())).valueOrNull!;
      final res = await repo.getById(id);
      expect(res.isOk, isTrue);
      expect(res.valueOrNull!.fundName, 'Petty Cash');
      expect(res.valueOrNull!.varianceCentavos, 20000);
    });
  });
}
