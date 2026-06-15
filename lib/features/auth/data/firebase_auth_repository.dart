import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';
import '../domain/bootstrap_rules.dart';
import '../domain/password_change_rules.dart';

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  FirebaseAuthRepository(this._auth, this._firestore);

  @override
  Stream<AppUser?> watchCurrentUser() {
    // Listen LIVE to the user document, not a one-shot get(): profile edits
    // (display name, photo, theme, accent) must propagate to every watcher —
    // router, theme controller, profile screen — without an auth-state change
    // or app restart. asyncExpand cancels the previous doc listener whenever
    // auth state changes (sign-out / account switch), so only the current
    // user's doc is ever observed.
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream<AppUser?>.value(null);
      return _firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .map((doc) =>
              doc.exists ? AppUser.fromMap(user.uid, doc.data()!) : null);
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

  @override
  Future<Result<bool>> needsBootstrap() async {
    try {
      final snap = await _firestore.collection('meta').doc('bootstrap').get();
      return Ok(!snap.exists);
    } catch (e) {
      developer.log('needsBootstrap failed', name: 'auth', error: e);
      return const Err(
        UnexpectedFailure('Could not check setup status. Please try again.'),
      );
    }
  }

  @override
  Future<Result<AppUser>> bootstrapFirstAdmin({
    required String email,
    required String password,
    required String displayName,
  }) async {
    // a. Pure validation before touching anything.
    final invalid = validateBootstrapInput(
      email: email,
      password: password,
      displayName: displayName,
    );
    if (invalid != null) return Err(invalid);

    final markerRef = _firestore.collection('meta').doc('bootstrap');

    // b. Client-side guard: fake_cloud_firestore (and offline races) do not
    // enforce the server rule, so refuse before creating any auth account if
    // the app has already been bootstrapped.
    try {
      final existing = await markerRef.get();
      if (existing.exists) {
        return const Err(PermissionFailure('Setup was already completed.'));
      }
    } catch (e) {
      developer.log('bootstrap precheck failed', name: 'auth', error: e);
      return const Err(
        UnexpectedFailure('Could not start setup. Please try again.'),
      );
    }

    final cleanEmail = email.trim();
    final cleanName = displayName.trim();

    // c. Create the auth account.
    final String uid;
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      uid = cred.user!.uid;
    } on FirebaseAuthException catch (e) {
      developer.log('bootstrap createUser failed', name: 'auth', error: e.code);
      return Err(AuthFailure(_signUpMessage(e.code)));
    } catch (e) {
      developer.log('bootstrap createUser failed', name: 'auth', error: e);
      return const Err(
        UnexpectedFailure('Could not create the account. Please try again.'),
      );
    }

    // d. Write both docs atomically.
    try {
      final batch = _firestore.batch();
      batch.set(_firestore.collection('users').doc(uid), {
        'role': 'admin',
        'companyId': '',
        'displayName': cleanName,
        'email': cleanEmail,
        'themeMode': 'system',
        'accentId': 'forest',
      });
      batch.set(markerRef, {
        'seeded': true,
        'seededByUid': uid,
        'seededAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } catch (e) {
      // e. Orphan cleanup: a lost write race must not leave a dangling auth
      // account. Delete it and sign out before surfacing the failure.
      developer.log('bootstrap batch write failed', name: 'auth', error: e);
      try {
        await _auth.currentUser?.delete();
      } catch (cleanupError) {
        developer.log('bootstrap orphan cleanup failed',
            name: 'auth', error: cleanupError);
      }
      await _auth.signOut();
      return const Err(
        PermissionFailure('Setup was already completed on another device.'),
      );
    }

    // f. Success.
    return Ok(AppUser(
      uid: uid,
      companyId: '',
      role: UserRole.admin,
      displayName: cleanName,
      email: cleanEmail,
    ));
  }

  @override
  Future<Result<void>> updateProfile({
    String? displayName,
    String? photoUrl,
    ThemeMode? themeMode,
    String? accentId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const Err(AuthFailure('You must be signed in to update your profile.'));
    }

    // Build a sparse map: only the fields the caller actually provided.
    final data = <String, dynamic>{};
    if (displayName != null) data['displayName'] = displayName;
    if (photoUrl != null) data['photoUrl'] = photoUrl;
    if (themeMode != null) data['themeMode'] = AppUser.themeModeName(themeMode);
    if (accentId != null) data['accentId'] = accentId;
    if (data.isEmpty) return const Ok(null);

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .set(data, SetOptions(merge: true));
      return const Ok(null);
    } catch (e) {
      developer.log('updateProfile failed', name: 'auth', error: e);
      return const Err(
        UnexpectedFailure('Could not save your profile. Please try again.'),
      );
    }
  }

  @override
  Future<Result<void>> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    // a. Pure validation first (min-length + reuse). Confirm-match is a UI
    // concern; pass newPassword for the confirm slot so this stays a no-op here.
    final invalid = validatePasswordChange(
      currentPassword: currentPassword,
      newPassword: newPassword,
      confirmPassword: newPassword,
    );
    if (invalid != null) return Err(invalid);

    // b. Must be signed in with a known email to reauthenticate.
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      return const Err(
        AuthFailure('You must be signed in to change your password.'),
      );
    }

    try {
      // c. Reauthenticate with the current password (Firebase requires a recent
      // login for updatePassword). A wrong/expired credential surfaces here.
      final cred =
          EmailAuthProvider.credential(email: email, password: currentPassword);
      await user.reauthenticateWithCredential(cred);

      // d. Set the new password.
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      // Log the CODE only — never the password or email.
      developer.log('changeOwnPassword auth failed', name: 'auth', error: e.code);
      return Err(_changePasswordFailure(e.code));
    } catch (e) {
      developer.log('changeOwnPassword failed', name: 'auth', error: e);
      return const Err(
        UnexpectedFailure('Could not change your password. Please try again.'),
      );
    }

    // e. Clear the forced-rotation flag AFTER Auth succeeds. The owner rule in
    // firestore.rules permits this single-field true->false self-write.
    try {
      await _firestore.collection('users').doc(user.uid).set(
        {'mustChangePassword': false},
        SetOptions(merge: true),
      );
    } catch (e) {
      developer.log('changeOwnPassword clear-flag failed',
          name: 'auth', error: e);
      // The password DID change; the live profile listener will retry on the
      // next snapshot. Surface a recoverable message so the user knows it took.
      return const Err(
        UnexpectedFailure(
          'Your password changed, but we could not refresh your account. '
          'Please sign in again.',
        ),
      );
    }

    return const Ok(null);
  }

  /// Maps a reauth/update-password `code` to a user-safe [Failure]. Wrong or
  /// expired credentials read as a current-password problem.
  Failure _changePasswordFailure(String code) => switch (code) {
        'wrong-password' || 'invalid-credential' =>
          const ValidationFailure('Your current password is incorrect.'),
        'weak-password' => const ValidationFailure(
            'That password is too weak '
            '(min $kBootstrapMinPasswordLength characters).'),
        'requires-recent-login' => const AuthFailure(
            'Please sign in again, then change your password.'),
        _ => const UnexpectedFailure(
            'Could not change your password. Please try again.'),
      };

  String _signUpMessage(String code) => switch (code) {
        'email-already-in-use' => 'That email address is already in use.',
        'invalid-email' => 'That email address is invalid.',
        'weak-password' => 'That password is too weak.',
        _ => 'Could not create the account. Please try again.',
      };

  String _message(String code) => switch (code) {
        'invalid-email' => 'That email address is invalid.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          'Incorrect email or password.',
        _ => 'Unable to sign in. Please try again.',
      };
}
