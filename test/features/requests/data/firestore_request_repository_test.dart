import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreRequestRepository repo;

  // Explicit Timestamps (NOT serverTimestamp): the fake resolves serverTimestamp
  // lazily, which makes orderBy on createdAt unreliable.
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

  group('watchReleasedByCompany', () {
    test('returns only that company\'s released requests, newest first', () async {
      await seed('r-old', companyId: 'c1', status: 'released', createdAt: DateTime(2026, 1, 1));
      await seed('r-new', companyId: 'c1', status: 'released', createdAt: DateTime(2026, 1, 5));
      await seed('ack', companyId: 'c1', status: 'acknowledged', createdAt: DateTime(2026, 1, 9));
      await seed('other', companyId: 'c2', status: 'released', createdAt: DateTime(2026, 1, 7));

      final list = await repo.watchReleasedByCompany('c1').first;

      expect(list.map((r) => r.id).toList(), ['r-new', 'r-old']);
      expect(list.every((r) => r.status == RequestStatus.released), isTrue);
      expect(list.every((r) => r.companyId == 'c1'), isTrue);
    });
  });

  group('watchApproverActedRecent', () {
    test('returns only acted statuses for the company, newest-first', () async {
      await seed('ack', companyId: 'c1', status: 'acknowledged', createdAt: DateTime(2026, 1, 1));
      await seed('ready', companyId: 'c1', status: 'readyForRelease', createdAt: DateTime(2026, 1, 4));
      await seed('rel', companyId: 'c1', status: 'released', createdAt: DateTime(2026, 1, 6));
      // Excluded statuses for the same company.
      await seed('pending', companyId: 'c1', status: 'pendingAck', createdAt: DateTime(2026, 1, 9));
      await seed('rejected', companyId: 'c1', status: 'rejected', createdAt: DateTime(2026, 1, 8));
      await seed('replenished', companyId: 'c1', status: 'replenished', createdAt: DateTime(2026, 1, 7));
      // Other company is never returned.
      await seed('other', companyId: 'c2', status: 'released', createdAt: DateTime(2026, 1, 5));

      final list = await repo.watchApproverActedRecent('c1', 25).first;

      expect(list.map((r) => r.id).toList(), ['rel', 'ready', 'ack']);
      expect(list.every((r) => r.companyId == 'c1'), isTrue);
      expect(
        list.every((r) => const [
              RequestStatus.acknowledged,
              RequestStatus.readyForRelease,
              RequestStatus.released,
            ].contains(r.status)),
        isTrue,
      );
    });

    test('respects the limit, keeping the newest', () async {
      await seed('a', companyId: 'c1', status: 'acknowledged', createdAt: DateTime(2026, 1, 1));
      await seed('b', companyId: 'c1', status: 'released', createdAt: DateTime(2026, 1, 3));
      await seed('c', companyId: 'c1', status: 'readyForRelease', createdAt: DateTime(2026, 1, 2));

      final list = await repo.watchApproverActedRecent('c1', 2).first;

      expect(list.map((r) => r.id).toList(), ['b', 'c']);
    });
  });

  group('watchReleasedAll', () {
    test('returns released across all companies, newest first', () async {
      await seed('a', companyId: 'c1', status: 'released', createdAt: DateTime(2026, 1, 1));
      await seed('b', companyId: 'c2', status: 'released', createdAt: DateTime(2026, 1, 3));
      await seed('c', companyId: 'c1', status: 'pendingAck', createdAt: DateTime(2026, 1, 4));
      await seed('d', companyId: 'c3', status: 'released', createdAt: DateTime(2026, 1, 2));

      final list = await repo.watchReleasedAll(100).first;

      expect(list.map((r) => r.id).toList(), ['b', 'd', 'a']);
      expect(list.every((r) => r.status == RequestStatus.released), isTrue);
    });

    test('respects the limit, keeping the newest', () async {
      await seed('a', companyId: 'c1', status: 'released', createdAt: DateTime(2026, 1, 1));
      await seed('b', companyId: 'c2', status: 'released', createdAt: DateTime(2026, 1, 3));
      await seed('c', companyId: 'c3', status: 'released', createdAt: DateTime(2026, 1, 2));

      final list = await repo.watchReleasedAll(2).first;

      expect(list.map((r) => r.id).toList(), ['b', 'c']);
    });
  });
}
