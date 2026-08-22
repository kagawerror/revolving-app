import '../../../core/error/failure.dart';
import 'bootstrap_rules.dart' show kBootstrapMinPasswordLength;

/// Pure validation for the user's own "change my password" form
/// (`ChangePasswordScreen`), the forced-rotation gate.
///
/// Returns `null` when valid, otherwise a [ValidationFailure] with a user-safe
/// message. No Firebase imports — this is the TDD seam the data layer calls
/// before reauthenticating. Rules:
///   * [currentPassword] must be non-empty (re-auth needs it).
///   * [newPassword] must be at least [kBootstrapMinPasswordLength] characters
///     (reuses the shared bootstrap constant so all password flows agree).
///   * [newPassword] must DIFFER from [currentPassword] (block reuse).
///   * [confirmPassword] must match [newPassword] character for character.
///
/// Passwords are NOT trimmed (leading/trailing spaces are legal) and are never
/// logged or persisted here.
ValidationFailure? validatePasswordChange({
  required String currentPassword,
  required String newPassword,
  required String confirmPassword,
}) {
  if (currentPassword.isEmpty) {
    return const ValidationFailure('Enter your current password.');
  }
  if (newPassword.length < kBootstrapMinPasswordLength) {
    return const ValidationFailure(
      'Use a password of at least $kBootstrapMinPasswordLength characters.',
    );
  }
  if (newPassword == currentPassword) {
    return const ValidationFailure(
      'Choose a password different from your current one.',
    );
  }
  if (newPassword != confirmPassword) {
    return const ValidationFailure('Passwords do not match.');
  }
  return null;
}
