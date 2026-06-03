import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  FirebaseAuthRepository(this._auth, this._firestore);

  @override
  Stream<AppUser?> watchCurrentUser() {
    return _auth.authStateChanges().asyncMap((user) async {
      if (user == null) return null;
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return null;
      return AppUser.fromMap(user.uid, doc.data()!);
    });
  }

  @override
  Future<Result<AppUser>> signIn(
      {required String email, required String password}) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      final uid = cred.user!.uid;
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) {
        await _auth.signOut();
        return const Err(AuthFailure('No profile is provisioned for this account.'));
      }
      return Ok(AppUser.fromMap(uid, doc.data()!));
    } on FirebaseAuthException catch (e) {
      return Err(AuthFailure(_message(e.code)));
    } catch (_) {
      return const Err(UnexpectedFailure('Sign-in failed. Please try again.'));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  String _message(String code) => switch (code) {
        'invalid-email' => 'That email address is invalid.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          'Incorrect email or password.',
        _ => 'Unable to sign in. Please try again.',
      };
}
