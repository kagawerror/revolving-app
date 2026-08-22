import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/domain/bootstrap_rules.dart';
import '../domain/user_admin_repository.dart';

/// Injectable seam for "create a Firebase Auth sign-in and return its uid".
///
/// The default implementation ([_realAccountCreator]) provisions the account on
/// a SECONDARY [FirebaseApp] so the calling admin's primary session is never
/// replaced. Tests pass a fake to drive success/error paths without Firebase.
/// The [password] is handed straight to Auth and must never be logged or stored.
typedef AccountCreator = Future<String> Function({
  required String email,
  required String password,
});

/// Admin-only Firestore maintenance of user profiles. Mirrors the bootstrap
/// user-doc shape from `FirebaseAuthRepository.bootstrapFirstAdmin`, so admin-
/// created profiles are interchangeable with self-created ones. No PII (email,
/// password) reaches the logs.
class FirestoreUserAdminRepository implements UserAdminRepository {
  final FirebaseFirestore _db;
  final AccountCreator _accountCreator;

  FirestoreUserAdminRepository(
    this._db, {
    AccountCreator? accountCreator,
  }) : _accountCreator = accountCreator ?? _realAccountCreator;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('users');

  @override
  Stream<List<AppUser>> watchAll() => _col
      .orderBy('displayName')
      .snapshots()
      .map((s) => s.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList());

  @override
  Future<Result<String>> createUserWithAccount({
    required String email,
    required String password,
    required String displayName,
    required UserRole role,
    required String companyId,
    required List<String> companyIds,
    List<String> assignedFundIds = const [],
  }) async {
    final cleanEmail = email.trim();
    final cleanName = displayName.trim();

    // 1. Create the auth account first (on a secondary app). On failure nothing
    // is written. The password is never logged.
    final String uid;
    try {
      uid = await _accountCreator(email: cleanEmail, password: password);
    } on FirebaseAuthException catch (e) {
      developer.log('createUserWithAccount auth failed',
          name: 'admin_users', error: e.code);
      return Err(mapSignUpError(e.code));
    } catch (e, st) {
      developer.log('createUserWithAccount auth failed',
          name: 'admin_users', error: e, stackTrace: st);
      return const Err(
        UnexpectedFailure('Could not create the account. Please try again.'),
      );
    }

    // 2. Guard against an existing profile at this uid (duplicate).
    final ref = _col.doc(uid);
    try {
      final existing = await ref.get();
      if (existing.exists) {
        return const Err(
          ValidationFailure('A profile already exists for that user ID.'),
        );
      }
    } catch (e, st) {
      developer.log('createUserWithAccount precheck failed',
          name: 'admin_users', error: e, stackTrace: st);
      return const Err(
        UnexpectedFailure(
          'Account created but profile setup failed. The email is now '
          'registered — contact support to finish provisioning, or have the '
          'user sign in to self-provision.',
        ),
      );
    }

    // 3. Write the bootstrap-shaped profile doc on the PRIMARY instance. The
    // password is intentionally NOT part of this map.
    try {
      await ref.set({
        'role': role.name,
        'companyId': companyId,
        'companyIds': companyIds,
        // Per-incharge fund scoping. Written atomically with companyIds in the
        // single profile-doc set (no transaction). Empty for non-incharge roles
        // and for a zero-fund incharge (the valid strict empty state).
        'assignedFundIds': assignedFundIds,
        'displayName': cleanName,
        'email': cleanEmail,
        'themeMode': 'system',
        'accentId': 'forest',
        // Force a first-login password change: the admin typed a temporary
        // password, so the user is gated to ChangePasswordScreen on first sign-in.
        'mustChangePassword': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      // 4. Auth succeeded but the profile write failed — the email is now
      // registered. Surface a recoverable message; log the real cause (no PII).
      developer.log('createUserWithAccount profile write failed',
          name: 'admin_users', error: e, stackTrace: st);
      return const Err(
        UnexpectedFailure(
          'Account created but profile setup failed. The email is now '
          'registered — contact support to finish provisioning, or have the '
          'user sign in to self-provision.',
        ),
      );
    }

    return Ok(uid);
  }

  @override
  Future<Result<void>> updateAssignment({
    required String uid,
    required UserRole role,
    required String companyId,
    required List<String> companyIds,
    required String displayName,
    List<String> assignedFundIds = const [],
  }) async {
    try {
      // ONLY the mutable assignment fields; email/theme/accent are left
      // untouched (identity + self-service presentation). assignedFundIds is
      // written atomically with companyIds in this single-doc update.
      await _col.doc(uid).update({
        'role': role.name,
        'companyId': companyId,
        'companyIds': companyIds,
        'assignedFundIds': assignedFundIds,
        'displayName': displayName,
      });
      return const Ok(null);
    } catch (e, st) {
      developer.log('updateAssignment failed',
          name: 'admin_users', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not update the profile.'));
    }
  }
}

/// Maps a [FirebaseAuthException] sign-up `code` to a user-safe [Failure].
/// Pure + top-level so it is unit-testable without Firebase.
Failure mapSignUpError(String code) => switch (code) {
      'email-already-in-use' =>
        const ValidationFailure('That email address is already in use.'),
      'invalid-email' =>
        const ValidationFailure('That email address is invalid.'),
      'weak-password' => ValidationFailure(
          'That password is too weak '
          '(min $kBootstrapMinPasswordLength characters).'),
      'operation-not-allowed' => const UnexpectedFailure(
          'Email/password accounts are disabled in Firebase.'),
      _ => const UnexpectedFailure(
          'Could not create the account. Please try again.'),
    };

/// Default [AccountCreator]: provisions the Firebase Auth account on a SECONDARY
/// [FirebaseApp] named `userCreation`, reusing the PRIMARY app's options at
/// runtime (this app initialises Firebase without `DefaultFirebaseOptions`, so
/// there is no generated options class to pass). Creating on a secondary app
/// means the calling admin's primary `FirebaseAuth.instance` session is never
/// touched.
///
/// The secondary app is always torn down in `finally` so a later add does not
/// hit `duplicate-app`; any leftover `userCreation` app from a crashed prior
/// attempt is defensively deleted on entry. The password is never logged.
///
/// NOTE: this real path cannot be unit-tested (it talks to live Firebase); it is
/// covered by the injected fake in tests plus a manual smoke test.
Future<String> _realAccountCreator({
  required String email,
  required String password,
}) async {
  const appName = 'userCreation';

  // Defensively clear any leftover secondary app from a crashed prior attempt.
  try {
    await Firebase.app(appName).delete();
  } catch (_) {
    // No leftover app — nothing to clean up.
  }

  final primary = Firebase.app();
  FirebaseApp? secondary;
  try {
    secondary = await Firebase.initializeApp(
      name: appName,
      options: primary.options,
    );
    final secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
    final cred = await secondaryAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = cred.user!.uid;
    await secondaryAuth.signOut();
    return uid;
  } finally {
    // ALWAYS tear down the secondary app to prevent `duplicate-app` next time.
    await secondary?.delete();
  }
}
