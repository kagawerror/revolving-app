import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/auth/data/firebase_auth_repository.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  late _MockAuth auth;
  late FakeFirebaseFirestore firestore;

  setUp(() {
    auth = _MockAuth();
    firestore = FakeFirebaseFirestore();
  });

  void signInAs(String uid) {
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
  }

  test('updateProfile merges new fields without clobbering role/companyId',
      () async {
    await firestore.collection('users').doc('u1').set({
      'companyId': 'c1',
      'role': 'incharge',
      'displayName': 'Ana',
      'email': 'ana@x.com',
    });
    signInAs('u1');
    final repo = FirebaseAuthRepository(auth, firestore);

    final res = await repo.updateProfile(
      displayName: 'Ana Reyes',
      photoUrl: 'https://cdn/p.jpg',
      themeMode: ThemeMode.dark,
      accentId: 'violet',
    );

    expect(res.isOk, isTrue);
    final doc = await firestore.collection('users').doc('u1').get();
    final data = doc.data()!;
    expect(data['displayName'], 'Ana Reyes');
    expect(data['photoUrl'], 'https://cdn/p.jpg');
    expect(data['themeMode'], 'dark');
    expect(data['accentId'], 'violet');
    // Merge must not clobber the admin-controlled fields.
    expect(data['companyId'], 'c1');
    expect(data['role'], 'incharge');
    expect(data['email'], 'ana@x.com');
  });

  test('updateProfile with no fields is a no-op Ok', () async {
    await firestore.collection('users').doc('u1').set({
      'companyId': 'c1',
      'role': 'incharge',
      'displayName': 'Ana',
      'email': 'ana@x.com',
    });
    signInAs('u1');
    final repo = FirebaseAuthRepository(auth, firestore);

    final res = await repo.updateProfile();

    expect(res.isOk, isTrue);
    final doc = await firestore.collection('users').doc('u1').get();
    expect(doc.data()!['displayName'], 'Ana');
  });

  test('updateProfile returns AuthFailure when signed out', () async {
    when(() => auth.currentUser).thenReturn(null);
    final repo = FirebaseAuthRepository(auth, firestore);

    final res = await repo.updateProfile(displayName: 'X');

    expect(res.failureOrNull, isA<AuthFailure>());
  });
}
