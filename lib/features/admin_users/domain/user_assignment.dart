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
/// so a non-admin role can only be tied to companies that actually exist.
///
/// Multi-company membership: a non-admin must have at least one company in
/// [companyIds], every member must exist, the list must be duplicate-free, and
/// [companyId] (the primary) must be one of [companyIds]. Admins carry neither a
/// primary nor any membership.
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
  required List<String> companyIds,
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
    if (companyId.isNotEmpty || companyIds.isNotEmpty) {
      return const ValidationFailure('Admins are not assigned to a company.');
    }
    return null;
  }
  // Non-admin: at least one membership, all real, no duplicates, and the
  // primary in the set. (UI dedups, but the domain function is self-protecting.)
  if (companyIds.isEmpty ||
      companyIds.toSet().length != companyIds.length ||
      !companyIds.every(existingCompanyIds.contains) ||
      !companyIds.contains(companyId)) {
    return const ValidationFailure('Select an existing company.');
  }
  return null;
}
