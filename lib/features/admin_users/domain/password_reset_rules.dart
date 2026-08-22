import '../../../core/error/failure.dart';
import '../../auth/domain/bootstrap_rules.dart' show kBootstrapMinPasswordLength;

/// Pure validation for the admin "set/reset another user's password" form.
///
/// Returns `null` when valid, otherwise a [ValidationFailure] with a user-safe
/// message. Mirrors the CREATE-path wording in `user_assignment.dart` so the
/// two flows agree on what a "good" password is. No Firebase imports — this is
/// the TDD seam. The password is never logged or persisted here.
///
/// [password] is intentionally NOT trimmed (leading/trailing spaces are legal
/// in a password); the confirmation must match it character for character.
ValidationFailure? validateNewPassword(String password, String confirmPassword) {
  if (password.length < kBootstrapMinPasswordLength) {
    return const ValidationFailure(
      'Use a password of at least $kBootstrapMinPasswordLength characters.',
    );
  }
  if (password != confirmPassword) {
    return const ValidationFailure('Passwords do not match.');
  }
  return null;
}

/// Total mapping from the admin-relay HTTP status to a user-safe [Failure].
///
/// Honors the fixed Worker contract: 400 bad input/weak, 401 unauthorized,
/// 403 not-admin, 404 target not found, anything else (incl. >=500) unexpected.
Failure mapSetPasswordStatus(int statusCode) {
  switch (statusCode) {
    case 400:
      return const ValidationFailure(
        'That password was rejected. Use at least '
        '$kBootstrapMinPasswordLength characters.',
      );
    case 401:
      return const AuthFailure('Your session expired. Sign in again.');
    case 403:
      return const PermissionFailure('Only admins can reset passwords.');
    case 404:
      return const NotFoundFailure('That user no longer exists.');
    default:
      return const UnexpectedFailure('Could not set the password. Try again.');
  }
}
