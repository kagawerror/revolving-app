import '../../../core/error/failure.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/domain/bootstrap_rules.dart' show isValidEmail;

/// Pure validation for an admin user-assignment submission (create or edit).
///
/// Returns `null` when valid, otherwise a [ValidationFailure] with a user-safe
/// message. No Firebase imports — the same rules are mirrored in
/// `firestore.rules` (admin-only writes to `users`).
///
/// [existingCompanyIds] is the set of real company ids (from `companiesProvider`)
/// so a non-admin role can only be tied to a company that actually exists.
///
/// Email is only checked when [validateEmail] is true (the CREATE path). On the
/// EDIT path the email is immutable identity carried through untouched, so the
/// caller passes `validateEmail: false`.
ValidationFailure? validateUserAssignment({
  required String uid,
  required String displayName,
  required String email,
  required UserRole role,
  required String companyId,
  required Set<String> existingCompanyIds,
  bool validateEmail = true,
}) {
  if (uid.trim().isEmpty) {
    return const ValidationFailure('A Firebase user ID is required.');
  }
  if (displayName.trim().isEmpty) {
    return const ValidationFailure('A display name is required.');
  }
  if (validateEmail && !isValidEmail(email)) {
    return const ValidationFailure('A valid email is required.');
  }
  if (role == UserRole.admin) {
    if (companyId.isNotEmpty) {
      return const ValidationFailure('Admins are not assigned to a company.');
    }
    return null;
  }
  if (companyId.isEmpty || !existingCompanyIds.contains(companyId)) {
    return const ValidationFailure('Select an existing company.');
  }
  return null;
}
