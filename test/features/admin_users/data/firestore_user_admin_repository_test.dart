// Implementing the sealed cloud_firestore reference/snapshot types is the only
// way to make a single write (`set`) throw while letting the duplicate-precheck
// read (`get`) succeed — FakeFirebaseFirestore never fails a write, so it can't
// exercise the "auth succeeded but profile write failed" recovery branch. These
// are test-only mocks; the analyzer's sealed-subtype warning is ignored above.
// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/admin_users/data/firestore_user_admin_repository.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';

class _MockDb extends Mock implements FirebaseFirestore {}

class _MockCol extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDoc extends Mock implements DocumentReference<Map<String, dynamic>> {}

class _MockSnap extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('createUserWithAccount', () {
    test('success: writes a bootstrap-shaped doc at the new uid with no '
        'password field', () async {
      final repo = FirestoreUserAdminRepository(
        db,
        accountCreator: ({required email, required password}) async =>
            'newuid123',
      );
      final res = await repo.createUserWithAccount(
        email: 'jane@acme.com',
        password: 'super-secret',
        displayName: 'Jane',
        role: UserRole.incharge,
        companyId: 'c1',
        companyIds: const ['c1', 'c2'],
      );
      expect(res.isOk, isTrue);
      expect(res.valueOrNull, 'newuid123');

      final doc = await db.collection('users').doc('newuid123').get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['role'], 'incharge');
      expect(data['companyId'], 'c1');
      expect(data['companyIds'], ['c1', 'c2']);
      expect(data['displayName'], 'Jane');
      expect(data['email'], 'jane@acme.com');
      expect(data['themeMode'], 'system');
      expect(data['accentId'], 'forest');
      // The password must never be persisted.
      expect(data.containsKey('password'), isFalse);
    });

    test('auth error: returns ValidationFailure and writes NO doc', () async {
      final repo = FirestoreUserAdminRepository(
        db,
        accountCreator: ({required email, required password}) async =>
            throw FirebaseAuthException(code: 'email-already-in-use'),
      );
      final res = await repo.createUserWithAccount(
        email: 'taken@acme.com',
        password: 'super-secret',
        displayName: 'Jane',
        role: UserRole.incharge,
        companyId: 'c1',
        companyIds: const ['c1'],
      );
      expect(res.failureOrNull, isA<ValidationFailure>());
      expect(res.failureOrNull!.message, 'That email address is already in use.');

      final users = await db.collection('users').get();
      expect(users.docs, isEmpty);
    });

    test('duplicate pre-read: existing profile at the uid blocks the write',
        () async {
      await db.collection('users').doc('newuid123').set({
        'role': 'manager',
        'companyId': 'c9',
        'displayName': 'Existing',
        'email': 'existing@acme.com',
        'themeMode': 'dark',
        'accentId': 'forest',
      });
      final repo = FirestoreUserAdminRepository(
        db,
        accountCreator: ({required email, required password}) async =>
            'newuid123',
      );
      final res = await repo.createUserWithAccount(
        email: 'jane@acme.com',
        password: 'super-secret',
        displayName: 'Jane',
        role: UserRole.incharge,
        companyId: 'c1',
        companyIds: const ['c1'],
      );
      expect(res.failureOrNull, isA<ValidationFailure>());
      expect(res.failureOrNull!.message,
          'A profile already exists for that user ID.');
      // Original doc untouched.
      final data = (await db.collection('users').doc('newuid123').get()).data()!;
      expect(data['displayName'], 'Existing');
      expect(data['role'], 'manager');
    });

    test('profile write fails AFTER the auth account is created: returns the '
        'recoverable UnexpectedFailure with the exact "Account created but '
        'profile setup failed" message', () async {
      // Auth succeeds (fake returns a uid), the duplicate-precheck read finds
      // no existing doc, then the profile `set` throws — the one path
      // FakeFirebaseFirestore can't model. Lock the exact user-facing string.
      final mockDb = _MockDb();
      final col = _MockCol();
      final doc = _MockDoc();
      final snap = _MockSnap();
      when(() => mockDb.collection('users')).thenReturn(col);
      when(() => col.doc('newuid123')).thenReturn(doc);
      when(() => doc.get()).thenAnswer((_) async => snap);
      when(() => snap.exists).thenReturn(false);
      when(() => doc.set(any())).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );

      final repo = FirestoreUserAdminRepository(
        mockDb,
        accountCreator: ({required email, required password}) async =>
            'newuid123',
      );
      final res = await repo.createUserWithAccount(
        email: 'jane@acme.com',
        password: 'super-secret',
        displayName: 'Jane',
        role: UserRole.incharge,
        companyId: 'c1',
        companyIds: const ['c1'],
      );

      expect(res.failureOrNull, isA<UnexpectedFailure>());
      expect(
        res.failureOrNull!.message,
        'Account created but profile setup failed. The email is now '
        'registered — contact support to finish provisioning, or have the '
        'user sign in to self-provision.',
      );
      // The write was actually attempted (not short-circuited earlier).
      verify(() => doc.set(any())).called(1);
    });
  });

  group('updateAssignment', () {
    test('touches only role, companyId, companyIds, displayName', () async {
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
        companyIds: const ['c2', 'c3'],
        displayName: 'New',
      );
      expect(res.isOk, isTrue);
      final data = (await db.collection('users').doc('u1').get()).data()!;
      expect(data['role'], 'manager');
      expect(data['companyId'], 'c2');
      expect(data['companyIds'], ['c2', 'c3']);
      expect(data['displayName'], 'New');
      // Untouched fields preserved.
      expect(data['email'], 'keep@acme.com');
      expect(data['themeMode'], 'dark');
      expect(data['accentId'], 'sunset');
      expect(data['photoUrl'], 'http://img');
    });
  });

  group('legacy compatibility', () {
    test('a doc without companyIds parses via AppUser.fromMap', () async {
      await db.collection('users').doc('legacy').set({
        'role': 'incharge',
        'companyId': 'c1',
        'displayName': 'Old',
        'email': 'old@acme.com',
      });
      final repo = FirestoreUserAdminRepository(db);
      final list = await repo.watchAll().first;
      final legacy = list.firstWhere((u) => u.uid == 'legacy');
      expect(legacy.companyIds, const <String>[]);
      // Backward-compat: membership resolves to the single primary company.
      expect(legacy.companyMemberships, ['c1']);
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
