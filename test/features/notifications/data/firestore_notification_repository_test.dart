import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/notifications/data/firestore_notification_repository.dart';

/// Data-layer tests for the admin cross-company notification fan-out.
/// [watchAllForRole] drops the companyId filter so an admin (who has no company
/// membership) sees every alert addressed to their role across all tenants,
/// newest-first; [watchForRole] stays company-scoped for everyone else.
void main() {
  late FakeFirebaseFirestore fake;
  late FirestoreNotificationRepository repo;

  setUp(() {
    fake = FakeFirebaseFirestore();
    repo = FirestoreNotificationRepository(fake);
  });

  Future<void> seed({
    required String id,
    required String companyId,
    required List<String> recipientRoles,
    required int createdAtMs,
  }) =>
      fake.collection('notifications').doc(id).set(<String, dynamic>{
        'companyId': companyId,
        'recipientRoles': recipientRoles,
        'type': 'requestReleased',
        'title': 't',
        'body': 'b',
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(createdAtMs),
        'readAt': null,
      });

  group('watchAllForRole (admin, cross-company)', () {
    test('returns admin-addressed docs across ALL companies, newest-first',
        () async {
      // Two companies, both with an admin-addressed alert.
      await seed(id: 'a', companyId: 'c1', recipientRoles: const [
        'admin',
        'superior',
        'manager',
        'ceo'
      ], createdAtMs: 100);
      await seed(id: 'b', companyId: 'c2', recipientRoles: const [
        'admin',
        'superior',
        'manager',
        'ceo'
      ], createdAtMs: 300);
      // An alert NOT addressed to admin must be excluded.
      await seed(
          id: 'c',
          companyId: 'c1',
          recipientRoles: const ['incharge'],
          createdAtMs: 200);

      final list = await repo.watchAllForRole('admin').first;

      // Both admin docs, regardless of company; the incharge-only doc excluded.
      expect(list.map((n) => n.id), ['b', 'a']);
      expect(list.every((n) => n.recipientRoles.contains('admin')), isTrue);
    });

    test('empty when no doc addresses the role', () async {
      await seed(
          id: 'a',
          companyId: 'c1',
          recipientRoles: const ['incharge'],
          createdAtMs: 100);
      final list = await repo.watchAllForRole('admin').first;
      expect(list, isEmpty);
    });
  });

  group('watchForRole (company-scoped, unchanged)', () {
    test('returns only the caller-company docs for the role', () async {
      await seed(
          id: 'a',
          companyId: 'c1',
          recipientRoles: const ['superior', 'manager', 'ceo'],
          createdAtMs: 100);
      await seed(
          id: 'b',
          companyId: 'c2',
          recipientRoles: const ['superior', 'manager', 'ceo'],
          createdAtMs: 200);

      final list = await repo.watchForRole('c1', 'manager').first;

      // Only the c1 doc — c2 is a different tenant and must not leak.
      expect(list.map((n) => n.id), ['a']);
    });
  });
}
