import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/auth/data/firebase_auth_repository.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

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
}
