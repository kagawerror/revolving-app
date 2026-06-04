import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/admin_users/data/firestore_user_admin_repository.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  AppUser user({
    String uid = 'u1',
    String companyId = 'c1',
    UserRole role = UserRole.incharge,
    String displayName = 'Jane',
    String email = 'jane@acme.com',
  }) =>
      AppUser(
        uid: uid,
        companyId: companyId,
        role: role,
        displayName: displayName,
        email: email,
      );

  group('createProfile', () {
    test('writes a bootstrap-shaped doc at the explicit uid', () async {
      final repo = FirestoreUserAdminRepository(db);
      final res = await repo.createProfile(user());
      expect(res.isOk, isTrue);
      final doc = await db.collection('users').doc('u1').get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['role'], 'incharge');
      expect(data['companyId'], 'c1');
      expect(data['displayName'], 'Jane');
      expect(data['email'], 'jane@acme.com');
      expect(data['themeMode'], 'system');
      expect(data['accentId'], 'forest');
    });

    test('rejects a duplicate uid without overwriting', () async {
      await db.collection('users').doc('u1').set({
        'role': 'manager',
        'companyId': 'c9',
        'displayName': 'Existing',
        'email': 'existing@acme.com',
        'themeMode': 'dark',
        'accentId': 'forest',
      });
      final repo = FirestoreUserAdminRepository(db);
      final res = await repo.createProfile(user());
      expect(res.failureOrNull, isA<ValidationFailure>());
      // Original doc untouched.
      final data = (await db.collection('users').doc('u1').get()).data()!;
      expect(data['displayName'], 'Existing');
      expect(data['role'], 'manager');
    });
  });

  group('updateAssignment', () {
    test('touches only role, companyId, displayName', () async {
      await db.collection('users').doc('u1').set({
        'role': 'employee',
        'companyId': 'c1',
        'displayName': 'Old',
        'email': 'keep@acme.com',
        'themeMode': 'dark',
        'accentId': 'sunset',
        'photoUrl': 'http://img',
      });
      final repo = FirestoreUserAdminRepository(db);
      final res = await repo.updateAssignment(
        uid: 'u1',
        role: UserRole.manager,
        companyId: 'c2',
        displayName: 'New',
      );
      expect(res.isOk, isTrue);
      final data = (await db.collection('users').doc('u1').get()).data()!;
      expect(data['role'], 'manager');
      expect(data['companyId'], 'c2');
      expect(data['displayName'], 'New');
      // Untouched fields preserved.
      expect(data['email'], 'keep@acme.com');
      expect(data['themeMode'], 'dark');
      expect(data['accentId'], 'sunset');
      expect(data['photoUrl'], 'http://img');
    });
  });

  group('watchAll', () {
    test('emits all profiles ordered by displayName', () async {
      await db.collection('users').doc('a').set({
        'role': 'incharge', 'companyId': 'c1',
        'displayName': 'Zoe', 'email': 'z@acme.com',
      });
      await db.collection('users').doc('b').set({
        'role': 'manager', 'companyId': 'c1',
        'displayName': 'Amy', 'email': 'a@acme.com',
      });
      final repo = FirestoreUserAdminRepository(db);
      final list = await repo.watchAll().first;
      expect(list.map((u) => u.displayName), ['Amy', 'Zoe']);
    });
  });
}
