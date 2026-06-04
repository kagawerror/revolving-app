import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/auth/data/firebase_auth_repository.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockUser extends Mock implements User {}

/// A Firestore facade that delegates every call to a real
/// [FakeFirebaseFirestore] (so the bootstrap pre-check `get()` works), except
/// [batch], which returns a batch whose [WriteBatch.commit] throws. This lets
/// us exercise the orphan-cleanup branch where the auth account is created but
/// the atomic write fails.
class _CommitFailingFirestore extends FakeFirebaseFirestore {
  @override
  WriteBatch batch() => _ThrowingBatch(super.batch());
}

/// Records writes against a delegate batch but fails on commit.
class _ThrowingBatch implements WriteBatch {
  _ThrowingBatch(this._delegate);

  final WriteBatch _delegate;

  @override
  Future<void> commit() => throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'simulated write race',
      );

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) =>
      _delegate.set(document, data, options);

  @override
  void update(DocumentReference document, Map<String, dynamic> data) =>
      _delegate.update(document, data);

  @override
  void delete(DocumentReference document) => _delegate.delete(document);
}

void main() {
  late _MockAuth auth;
  late FirebaseFirestore firestore;
  setUp(() {
    auth = _MockAuth();
    firestore = _MockFirestore();
  });

  test('signIn maps wrong-password to AuthFailure', () async {
    when(() => auth.signInWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'))).thenThrow(
      FirebaseAuthException(code: 'wrong-password'),
    );
    final repo = FirebaseAuthRepository(auth, firestore);
    final res = await repo.signIn(email: 'a@b.com', password: 'x');
    expect(res.failureOrNull, isA<AuthFailure>());
  });

  test('wrong-password and user-not-found map to identical non-leaking message',
      () async {
    final repo = FirebaseAuthRepository(auth, firestore);

    when(() => auth.signInWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'))).thenThrow(
      FirebaseAuthException(code: 'wrong-password'),
    );
    final resWrong = await repo.signIn(email: 'a@b.com', password: 'x');

    when(() => auth.signInWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'))).thenThrow(
      FirebaseAuthException(code: 'user-not-found'),
    );
    final resNotFound = await repo.signIn(email: 'a@b.com', password: 'x');

    expect(resWrong.failureOrNull!.message, 'Incorrect email or password.');
    expect(resNotFound.failureOrNull!.message, 'Incorrect email or password.');
  });

  group('bootstrap', () {
    late _MockAuth auth;
    late FakeFirebaseFirestore firestore;

    setUp(() {
      auth = _MockAuth();
      firestore = FakeFirebaseFirestore();
    });

    void stubCreateUser(String uid) {
      final user = _MockUser();
      when(() => user.uid).thenReturn(uid);
      final cred = _MockUserCredential();
      when(() => cred.user).thenReturn(user);
      when(() => auth.createUserWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => cred);
    }

    test('needsBootstrap is true when no marker exists', () async {
      final repo = FirebaseAuthRepository(auth, firestore);
      final res = await repo.needsBootstrap();
      expect(res.valueOrNull, isTrue);
    });

    test('needsBootstrap is false when the marker exists', () async {
      await firestore.collection('meta').doc('bootstrap').set({'seeded': true});
      final repo = FirebaseAuthRepository(auth, firestore);
      final res = await repo.needsBootstrap();
      expect(res.valueOrNull, isFalse);
    });

    test('happy path writes user + marker and returns the admin', () async {
      stubCreateUser('admin-uid');
      final repo = FirebaseAuthRepository(auth, firestore);

      final res = await repo.bootstrapFirstAdmin(
        email: 'admin@acme.com',
        password: 'secret1',
        displayName: '  Ada  ',
      );

      final user = res.valueOrNull;
      expect(user, isNotNull);
      expect(user!.uid, 'admin-uid');
      expect(user.role, UserRole.admin);
      expect(user.companyId, '');
      expect(user.displayName, 'Ada');
      expect(user.email, 'admin@acme.com');

      final userDoc =
          await firestore.collection('users').doc('admin-uid').get();
      expect(userDoc.data()!['role'], 'admin');
      expect(userDoc.data()!['companyId'], '');
      expect(userDoc.data()!['displayName'], 'Ada');
      expect(userDoc.data()!['email'], 'admin@acme.com');

      final marker =
          await firestore.collection('meta').doc('bootstrap').get();
      expect(marker.exists, isTrue);
      expect(marker.data()!['seeded'], true);
      expect(marker.data()!['seededByUid'], 'admin-uid');
    });

    test('refuses when already seeded and creates no auth account', () async {
      await firestore.collection('meta').doc('bootstrap').set({
        'seeded': true,
        'seededByUid': 'someone',
      });
      final repo = FirebaseAuthRepository(auth, firestore);

      final res = await repo.bootstrapFirstAdmin(
        email: 'admin@acme.com',
        password: 'secret1',
        displayName: 'Ada',
      );

      expect(res.failureOrNull, isA<PermissionFailure>());
      verifyNever(() => auth.createUserWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ));
    });

    test(
        'orphan cleanup: batch commit failure deletes the auth account, '
        'signs out, and returns PermissionFailure', () async {
      // System is not yet seeded (no meta/bootstrap marker), so the pre-check
      // get() sees an unseeded state and the repo proceeds to create the auth
      // account...
      final commitFailingFirestore = _CommitFailingFirestore();

      // ...createUser succeeds and yields a uid...
      final user = _MockUser();
      when(() => user.uid).thenReturn('orphan-uid');
      when(() => user.delete()).thenAnswer((_) async {});
      final cred = _MockUserCredential();
      when(() => cred.user).thenReturn(user);
      when(() => auth.createUserWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => cred);

      // ...the just-created account is the current user the repo cleans up...
      when(() => auth.currentUser).thenReturn(user);
      when(() => auth.signOut()).thenAnswer((_) async {});

      final repo =
          FirebaseAuthRepository(auth, commitFailingFirestore);

      final res = await repo.bootstrapFirstAdmin(
        email: 'admin@acme.com',
        password: 'secret1',
        displayName: 'Ada',
      );

      expect(res.failureOrNull, isA<PermissionFailure>());
      verify(() => user.delete()).called(1);
      verify(() => auth.signOut()).called(1);
    });

    test('email-already-in-use maps to AuthFailure with no Firestore writes',
        () async {
      when(() => auth.createUserWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));
      final repo = FirebaseAuthRepository(auth, firestore);

      final res = await repo.bootstrapFirstAdmin(
        email: 'admin@acme.com',
        password: 'secret1',
        displayName: 'Ada',
      );

      expect(res.failureOrNull, isA<AuthFailure>());
      final marker =
          await firestore.collection('meta').doc('bootstrap').get();
      expect(marker.exists, isFalse);
    });
  });
}
