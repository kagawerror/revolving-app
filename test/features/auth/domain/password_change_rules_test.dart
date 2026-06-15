import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/auth/domain/bootstrap_rules.dart';
import 'package:rev_app/features/auth/domain/password_change_rules.dart';

void main() {
  // A new password that comfortably clears the min-length bar, reused across
  // the happy-path and the non-length failure cases.
  final good = 'a' * kBootstrapMinPasswordLength;

  group('validatePasswordChange', () {
    test('returns null when current/new/confirm are all valid', () {
      expect(
        validatePasswordChange(
          currentPassword: 'oldpassword',
          newPassword: good,
          confirmPassword: good,
        ),
        isNull,
      );
    });

    test('rejects an empty current password', () {
      final result = validatePasswordChange(
        currentPassword: '',
        newPassword: good,
        confirmPassword: good,
      );
      expect(result, isA<ValidationFailure>());
    });

    test('rejects a new password shorter than the minimum', () {
      final short = 'a' * (kBootstrapMinPasswordLength - 1);
      final result = validatePasswordChange(
        currentPassword: 'oldpassword',
        newPassword: short,
        confirmPassword: short,
      );
      expect(result, isA<ValidationFailure>());
    });

    test('rejects reusing the current password', () {
      final result = validatePasswordChange(
        currentPassword: good,
        newPassword: good,
        confirmPassword: good,
      );
      expect(result, isA<ValidationFailure>());
    });

    test('rejects a confirmation that does not match', () {
      final result = validatePasswordChange(
        currentPassword: 'oldpassword',
        newPassword: good,
        confirmPassword: '${good}x',
      );
      expect(result, isA<ValidationFailure>());
    });
  });
}
