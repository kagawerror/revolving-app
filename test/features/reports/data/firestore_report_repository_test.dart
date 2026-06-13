import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/reports/data/firestore_report_repository.dart';
import 'package:rev_app/features/reports/domain/report_period.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreReportRepository repo;

  final window = periodWindow(PeriodGranularity.month, DateTime(2026, 6, 10));

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreReportRepository(db);
  });

  Future<void> seedRequest({
    required String id,
    required String companyId,
    DateTime? releasedAt,
    int centavos = 10000,
  }) {
    return db.collection('requests').doc(id).set({
      'companyId': companyId,
      'fundId': 'f1',
      'createdByUid': 'u1',
      'beneficiaryName': 'Jane',
      'amountCentavos': centavos,
      'purpose': 'Fuel',
      'proofImageUrl': '',
      'status': 'released',
      'createdAt': Timestamp.fromDate(DateTime(2026, 6, 1)),
      if (releasedAt != null) 'releasedAt': Timestamp.fromDate(releasedAt),
    });
  }

  Future<void> seedRep({
    required String id,
    required String companyId,
    required String status,
    DateTime? decidedAt,
    int centavos = 50000,
  }) {
    return db.collection('replenishments').doc(id).set({
      'companyId': companyId,
      'fundId': 'f1',
      'status': status,
      'requestIds': ['a', 'b'],
      'totalCentavos': centavos,
      'reportNotes': '',
      'createdByUid': 'u1',
      'createdAt': Timestamp.fromDate(DateTime(2026, 6, 1)),
      if (decidedAt != null) 'decidedAt': Timestamp.fromDate(decidedAt),
    });
  }

  group('fetchReleasedForReport', () {
    test('returns only in-window, own-company released requests', () async {
      await seedRequest(id: 'in', companyId: 'c1', releasedAt: DateTime(2026, 6, 5));
      await seedRequest(id: 'before', companyId: 'c1', releasedAt: DateTime(2026, 5, 31));
      await seedRequest(id: 'after', companyId: 'c1', releasedAt: DateTime(2026, 7, 2));
      await seedRequest(id: 'noRelease', companyId: 'c1', releasedAt: null);
      // Foreign company, in-window: must NOT leak.
      await seedRequest(id: 'foreign', companyId: 'c2', releasedAt: DateTime(2026, 6, 6));

      final res = await repo.fetchReleasedForReport('c1', window);
      expect(res, isA<Ok>());
      final ids = (res as Ok).value.items.map((r) => r.id).toSet();
      expect(ids, {'in'});
    });
  });

  group('fetchApprovedReplenishments', () {
    test('returns only approved, in-window, own-company', () async {
      await seedRep(id: 'in', companyId: 'c1', status: 'approved', decidedAt: DateTime(2026, 6, 5));
      await seedRep(id: 'submitted', companyId: 'c1', status: 'submitted', decidedAt: DateTime(2026, 6, 5));
      await seedRep(id: 'after', companyId: 'c1', status: 'approved', decidedAt: DateTime(2026, 7, 3));
      await seedRep(id: 'foreign', companyId: 'c2', status: 'approved', decidedAt: DateTime(2026, 6, 6));

      final res = await repo.fetchApprovedReplenishments('c1', window);
      expect(res, isA<Ok>());
      final ids = (res as Ok).value.items.map((r) => r.id).toSet();
      expect(ids, {'in'});
    });
  });
}
