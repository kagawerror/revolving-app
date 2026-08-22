import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/admin_users/data/firestore_user_admin_repository.dart';

void main() {
  group('mapSignUpError', () {
    test('email-already-in-use -> ValidationFailure', () {
      final f = mapSignUpError('email-already-in-use');
      expect(f, isA<ValidationFailure>());
      expect(f.message, 'That email address is already in use.');
    });

    test('invalid-email -> ValidationFailure', () {
      final f = mapSignUpError('invalid-email');
      expect(f, isA<ValidationFailure>());
      expect(f.message, 'That email address is invalid.');
    });

    test('weak-password -> ValidationFailure', () {
      final f = mapSignUpError('weak-password');
      expect(f, isA<ValidationFailure>());
      expect(f.message, 'That password is too weak (min 6 characters).');
    });

    test('operation-not-allowed -> UnexpectedFailure', () {
      final f = mapSignUpError('operation-not-allowed');
      expect(f, isA<UnexpectedFailure>());
      expect(f.message, 'Email/password accounts are disabled in Firebase.');
    });

    test('unknown code -> UnexpectedFailure', () {
      final f = mapSignUpError('something-else');
      expect(f, isA<UnexpectedFailure>());
      expect(f.message, 'Could not create the account. Please try again.');
    });
  });
}
