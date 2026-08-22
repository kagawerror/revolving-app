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

  group('watchOutstandingByCompany', () {
    test('returns the company\'s outstanding (released/acknowledged/disputed) '
        'requests, newest first', () async {
      await seed('rel', companyId: 'c1', status: 'released', createdAt: DateTime(2026, 1, 1));
      await seed('ack', companyId: 'c1', status: 'acknowledged', createdAt: DateTime(2026, 1, 9));
      await seed('disp', companyId: 'c1', status: 'disputed', createdAt: DateTime(2026, 1, 5));
      // Excluded statuses for the same company.
      await seed('created', companyId: 'c1', status: 'created', createdAt: DateTime(2026, 1, 11));
      await seed('rejected', companyId: 'c1', status: 'rejected', createdAt: DateTime(2026, 1, 10));
      await seed('replenished', companyId: 'c1', status: 'replenished', createdAt: DateTime(2026, 1, 8));
      // Other company is never returned.
      await seed('other', companyId: 'c2', status: 'released', createdAt: DateTime(2026, 1, 7));

      final list = await repo.watchOutstandingByCompany('c1').first;

      expect(list.map((r) => r.id).toList(), ['ack', 'disp', 'rel']);
      expect(list.every((r) => r.companyId == 'c1'), isTrue);
      expect(
        list.every((r) => RequestStatus.replenishable.contains(r.status)),
        isTrue,
      );
    });
  });

  group('watchApproverActedRecent', () {
    test('returns only acted statuses for the company, newest-first', () async {
      await seed('ack', companyId: 'c1', status: 'acknowledged', createdAt: DateTime(2026, 1, 1));
      await seed('disp', companyId: 'c1', status: 'disputed', createdAt: DateTime(2026, 1, 4));
      await seed('rel', companyId: 'c1', status: 'released', createdAt: DateTime(2026, 1, 6));
      // Excluded statuses for the same company.
      await seed('created', companyId: 'c1', status: 'created', createdAt: DateTime(2026, 1, 9));
      await seed('rejected', companyId: 'c1', status: 'rejected', createdAt: DateTime(2026, 1, 8));
      await seed('replenished', companyId: 'c1', status: 'replenished', createdAt: DateTime(2026, 1, 7));
      // Other company is never returned.
      await seed('other', companyId: 'c2', status: 'released', createdAt: DateTime(2026, 1, 5));

      final list = await repo.watchApproverActedRecent('c1', 25).first;

      expect(list.map((r) => r.id).toList(), ['rel', 'disp', 'ack']);
      expect(list.every((r) => r.companyId == 'c1'), isTrue);
      expect(
        list.every((r) => const [
              RequestStatus.acknowledged,
              RequestStatus.disputed,
              RequestStatus.released,
            ].contains(r.status)),
        isTrue,
      );
    });

    test('respects the limit, keeping the newest', () async {
      await seed('a', companyId: 'c1', status: 'acknowledged', createdAt: DateTime(2026, 1, 1));
      await seed('b', companyId: 'c1', status: 'released', createdAt: DateTime(2026, 1, 3));
      await seed('c', companyId: 'c1', status: 'disputed', createdAt: DateTime(2026, 1, 2));

      final list = await repo.watchApproverActedRecent('c1', 2).first;

      expect(list.map((r) => r.id).toList(), ['b', 'c']);
    });
  });

  group('watchOutstandingAll', () {
    test('returns outstanding (released/acknowledged/disputed) across all '
        'companies, newest first', () async {
      await seed('a', companyId: 'c1', status: 'released', createdAt: DateTime(2026, 1, 1));
      await seed('b', companyId: 'c2', status: 'acknowledged', createdAt: DateTime(2026, 1, 3));
      await seed('d', companyId: 'c3', status: 'disputed', createdAt: DateTime(2026, 1, 2));
      // Excluded statuses (any company).
      await seed('c', companyId: 'c1', status: 'pendingAck', createdAt: DateTime(2026, 1, 4));
      await seed('rej', companyId: 'c2', status: 'rejected', createdAt: DateTime(2026, 1, 5));
      await seed('repl', companyId: 'c3', status: 'replenished', createdAt: DateTime(2026, 1, 6));

      final list = await repo.watchOutstandingAll(100).first;

      expect(list.map((r) => r.id).toList(), ['b', 'd', 'a']);
      expect(
        list.every((r) => RequestStatus.replenishable.contains(r.status)),
        isTrue,
      );
    });

    test('respects the limit, keeping the newest', () async {
      await seed('a', companyId: 'c1', status: 'released', createdAt: DateTime(2026, 1, 1));
      await seed('b', companyId: 'c2', status: 'acknowledged', createdAt: DateTime(2026, 1, 3));
      await seed('c', companyId: 'c3', status: 'disputed', createdAt: DateTime(2026, 1, 2));

      final list = await repo.watchOutstandingAll(2).first;

      expect(list.map((r) => r.id).toList(), ['b', 'c']);
    });
  });
}
