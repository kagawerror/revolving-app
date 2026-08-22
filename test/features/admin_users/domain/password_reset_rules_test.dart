import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/auth/domain/bootstrap_rules.dart';
import 'package:rev_app/features/admin_users/domain/password_reset_rules.dart';

void main() {
  group('validateNewPassword', () {
    test('rejects a too-short password with the create-path wording', () {
      final short = 'a' * (kBootstrapMinPasswordLength - 1);
      final result = validateNewPassword(short, short);
      expect(result, isA<ValidationFailure>());
      expect(
        result!.message,
        'Use a password of at least $kBootstrapMinPasswordLength characters.',
      );
    });

    test('rejects a mismatch when length is fine', () {
      final pw = 'a' * kBootstrapMinPasswordLength;
      final result = validateNewPassword(pw, '${pw}x');
      expect(result, isA<ValidationFailure>());
      expect(result!.message, 'Passwords do not match.');
    });

    test('returns null when valid', () {
      final pw = 'a' * kBootstrapMinPasswordLength;
      expect(validateNewPassword(pw, pw), isNull);
    });

    test('does not trim — leading/trailing spaces are significant', () {
      final pw = 'a' * kBootstrapMinPasswordLength;
      // Same length, but confirm differs by a trailing space.
      expect(validateNewPassword(pw, '$pw '), isA<ValidationFailure>());
    });
  });

  group('mapSetPasswordStatus', () {
    test('400 -> ValidationFailure', () {
      final f = mapSetPasswordStatus(400);
      expect(f, isA<ValidationFailure>());
      expect(
        f.message,
        'That password was rejected. Use at least '
        '$kBootstrapMinPasswordLength characters.',
      );
    });

    test('401 -> AuthFailure', () {
      final f = mapSetPasswordStatus(401);
      expect(f, isA<AuthFailure>());
      expect(f.message, 'Your session expired. Sign in again.');
    });

    test('403 -> PermissionFailure', () {
      final f = mapSetPasswordStatus(403);
      expect(f, isA<PermissionFailure>());
      expect(f.message, 'Only admins can reset passwords.');
    });

    test('404 -> NotFoundFailure', () {
      final f = mapSetPasswordStatus(404);
      expect(f, isA<NotFoundFailure>());
      expect(f.message, 'That user no longer exists.');
    });

    test('500 -> UnexpectedFailure', () {
      final f = mapSetPasswordStatus(500);
      expect(f, isA<UnexpectedFailure>());
      expect(f.message, 'Could not set the password. Try again.');
    });

    test('any other code -> UnexpectedFailure (total function)', () {
      expect(mapSetPasswordStatus(418), isA<UnexpectedFailure>());
      expect(mapSetPasswordStatus(302), isA<UnexpectedFailure>());
      expect(mapSetPasswordStatus(0), isA<UnexpectedFailure>());
    });
  });
}
