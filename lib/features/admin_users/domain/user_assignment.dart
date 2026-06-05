import '../../../core/error/failure.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/domain/bootstrap_rules.dart'
    show isValidEmail, kBootstrapMinPasswordLength;

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
///
/// Password: [password]/[confirmPassword] are CREATE-only. On the EDIT path the
/// caller passes `null` for both and the password branch is skipped. On CREATE
/// the password must be at least [kBootstrapMinPasswordLength] characters and
/// must match its confirmation. This check runs before the role/company branch
/// so a credential typo is surfaced first. The password is never logged or
/// stored here — this is pure validation only.
ValidationFailure? validateUserAssignment({
  required String displayName,
  required String email,
  required UserRole role,
  required String companyId,
  required List<String> companyIds,
  required Set<String> existingCompanyIds,
  String? password,
  String? confirmPassword,
  bool validateEmail = true,
}) {
  if (displayName.trim().isEmpty) {
    return const ValidationFailure('A display name is required.');
  }
  if (validateEmail && !isValidEmail(email)) {
    return const ValidationFailure('A valid email is required.');
  }
  // CREATE-only credential check (EDIT passes password == null). Runs before
  // role branching so a bad/mismatched password is reported first.
  if (password != null) {
    if (password.length < kBootstrapMinPasswordLength) {
      return const ValidationFailure(
        'Use a password of at least $kBootstrapMinPasswordLength characters.',
      );
    }
    if (password != confirmPassword) {
      return const ValidationFailure('Passwords do not match.');
    }
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
