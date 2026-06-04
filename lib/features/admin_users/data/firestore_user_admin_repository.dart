import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../auth/domain/app_user.dart';
import '../domain/user_admin_repository.dart';

/// Admin-only Firestore maintenance of user profiles. Mirrors the bootstrap
/// user-doc shape from `FirebaseAuthRepository.bootstrapFirstAdmin`, so admin-
/// created profiles are interchangeable with self-created ones. No PII reaches
/// the logs.
class FirestoreUserAdminRepository implements UserAdminRepository {
  final FirebaseFirestore _db;
  FirestoreUserAdminRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('users');

  @override
  Stream<List<AppUser>> watchAll() => _col
      .orderBy('displayName')
      .snapshots()
      .map((s) => s.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList());

  @override
  Future<Result<void>> createProfile(AppUser user) async {
    try {
      final ref = _col.doc(user.uid);
      final existing = await ref.get();
      if (existing.exists) {
        return const Err(
          ValidationFailure('A profile already exists for that user ID.'),
        );
      }
      // Bootstrap-shaped doc: same keys + presentation defaults as the founding
      // admin profile so every profile reads identically.
      await ref.set({
        'role': user.role.name,
        'companyId': user.companyId,
        'displayName': user.displayName,
        'email': user.email,
        'themeMode': 'system',
        'accentId': 'forest',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return const Ok(null);
    } catch (e, st) {
      developer.log('createProfile failed',
          name: 'admin_users', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not create the profile.'));
    }
  }

  @override
  Future<Result<void>> updateAssignment({
    required String uid,
    required UserRole role,
    required String companyId,
    required String displayName,
  }) async {
    try {
      // ONLY the three mutable assignment fields; email/theme/accent are left
      // untouched (identity + self-service presentation).
      await _col.doc(uid).update({
        'role': role.name,
        'companyId': companyId,
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
