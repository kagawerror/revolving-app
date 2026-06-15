import '../../auth/domain/app_user.dart';
import '../domain/admin_password_repository.dart';
import '../domain/password_reset_rules.dart';
import '../domain/user_admin_repository.dart';

/// Orchestrates the DEDICATED admin "reset password" action, returning `null`
/// on success or a user-safe error message on failure (the dialog stays open and
/// surfaces it). Pure of Flutter/Firebase: the repositories are injected so this
/// is the unit-test seam.
///
/// Ordering mirrors [submitUserForm]'s inline reset branch and is load-bearing:
///   1. Validate [newPassword] via the shared [validateNewPassword] seam; an
///      invalid password short-circuits BEFORE any side effect.
///   2. Set the password via the admin-relay Worker FIRST. On failure, surface
///      its message and do NOT flag the account.
///   3. Only after the password set succeeds, stamp `mustChangePassword = true`
///      so the target hits the change-password gate on next sign-in. If the flag
///      write fails the password IS already reset, so we surface a recoverable
///      message rather than implying the whole action failed.
///
/// [newPassword] is transient: handed straight to the repositories, never logged
/// or persisted here.
Future<String?> resetUserPassword({
  required AppUser target,
  required String newPassword,
  required AdminPasswordRepository adminPasswordRepository,
  required UserAdminRepository userAdminRepository,
}) async {
  // 1. Pure validation (min length). Confirm-match is enforced by the dialog;
  // pass newPassword for the confirm slot so this stays a length/non-empty check.
  final invalid = validateNewPassword(newPassword, newPassword);
  if (invalid != null) return invalid.message;

  // 2. Password set FIRST, against the separate admin-relay system.
  final pwRes = await adminPasswordRepository.setUserPassword(
    uid: target.uid,
    newPassword: newPassword,
  );
  if (pwRes.failureOrNull != null) return pwRes.failureOrNull!.message;

  // 3. Force a first-login rotation. Recoverable if it fails (password is set).
  final flagRes = await userAdminRepository.setMustChangePassword(
    uid: target.uid,
    value: true,
  );
  if (flagRes.failureOrNull != null) {
    return "Password was reset, but couldn't flag the account. Try again.";
  }

  return null; // success
}
