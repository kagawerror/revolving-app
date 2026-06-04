import '../../../core/error/failure.dart';

/// Minimum password length Firebase Auth accepts.
const int kBootstrapMinPasswordLength = 6;

/// Validates the founding-admin setup form before any account is created.
///
/// Pure decision logic (no Firebase): returns `null` when the input is valid,
/// otherwise a [ValidationFailure] with a user-safe message. Whitespace around
/// the name and email is ignored (the same trimmed values the repository
/// persists), so a name that is only spaces counts as blank.
ValidationFailure? validateBootstrapInput({
  required String email,
  required String password,
  required String displayName,
}) {
  if (displayName.trim().isEmpty) {
    return const ValidationFailure('Enter a display name.');
  }
  final trimmedEmail = email.trim();
  if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
    return const ValidationFailure('Enter a valid email address.');
  }
  if (password.length < kBootstrapMinPasswordLength) {
    return const ValidationFailure(
      'Use a password of at least $kBootstrapMinPasswordLength characters.',
    );
  }
  return null;
}
