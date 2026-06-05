import '../../../core/error/result.dart';
import '../../auth/domain/app_user.dart';

/// Admin-only maintenance of user profiles. Implemented in
/// `data/firestore_user_admin_repository.dart` (CODER: Firestore writes,
/// `Result` mapping, and audit/permission handling live there).
abstract interface class UserAdminRepository {
  /// All user profiles across all companies (admin console list).
  Stream<List<AppUser>> watchAll();

  /// Links a profile doc to an already-provisioned Firebase Auth user
  /// (free-tier: no Cloud Functions, so the sign-in is created in the console
  /// first and the UID pasted in).
  Future<Result<void>> createProfile(AppUser user);

  /// Updates the mutable assignment fields of an existing profile. UID and email
  /// are immutable identity and are not part of this call.
  Future<Result<void>> updateAssignment({
    required String uid,
    required UserRole role,
    required String companyId,
    required List<String> companyIds,
    required String displayName,
  });
}
