import '../../../core/error/result.dart';
import '../../auth/domain/app_user.dart';

/// Admin-only maintenance of user profiles. Implemented in
/// `data/firestore_user_admin_repository.dart` (CODER: Firestore writes,
/// `Result` mapping, and audit/permission handling live there).
abstract interface class UserAdminRepository {
  /// All user profiles across all companies (admin console list).
  Stream<List<AppUser>> watchAll();

  /// Creates the Firebase Auth sign-in (on a secondary app, so the calling
  /// admin stays signed in) AND writes the profile doc on the primary instance.
  /// [password] is never stored or logged. Returns the new uid on success.
  Future<Result<String>> createUserWithAccount({
    required String email,
    required String password,
    required String displayName,
    required UserRole role,
    required String companyId,
    required List<String> companyIds,
    List<String> assignedFundIds = const [],
  });

  /// Updates the mutable assignment fields of an existing profile. UID and email
  /// are immutable identity and are not part of this call.
  Future<Result<void>> updateAssignment({
    required String uid,
    required UserRole role,
    required String companyId,
    required List<String> companyIds,
    required String displayName,
    List<String> assignedFundIds = const [],
  });
}
