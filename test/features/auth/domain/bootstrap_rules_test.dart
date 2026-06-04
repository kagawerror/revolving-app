import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/auth/domain/bootstrap_rules.dart';

void main() {
  group('validateBootstrapInput', () {
    test('accepts valid input', () {
      final result = validateBootstrapInput(
        email: 'admin@acme.com',
        password: 'secret1',
        displayName: 'Ada',
      );
      expect(result, isNull);
    });

    test('rejects a blank display name', () {
      final result = validateBootstrapInput(
        email: 'admin@acme.com',
        password: 'secret1',
        displayName: '   ',
      );
      expect(result, isA<ValidationFailure>());
    });

    test('rejects an email without @', () {
      final result = validateBootstrapInput(
        email: 'admin-acme.com',
        password: 'secret1',
        displayName: 'Ada',
      );
      expect(result, isA<ValidationFailure>());
    });

    test('rejects an empty email', () {
      final result = validateBootstrapInput(
        email: '',
        password: 'secret1',
        displayName: 'Ada',
      );
      expect(result, isA<ValidationFailure>());
    });

    test('rejects a password shorter than 6 characters', () {
      final result = validateBootstrapInput(
        email: 'admin@acme.com',
        password: '12345',
        displayName: 'Ada',
      );
      expect(result, isA<ValidationFailure>());
    });

    test('accepts a password of exactly 6 characters', () {
      final result = validateBootstrapInput(
        email: 'admin@acme.com',
        password: '123456',
        displayName: 'Ada',
      );
      expect(result, isNull);
    });

    test('respects trimming of the display name', () {
      // Surrounding whitespace should not make a real name look blank.
      final result = validateBootstrapInput(
        email: 'admin@acme.com',
        password: 'secret1',
        displayName: '  Ada  ',
      );
      expect(result, isNull);
    });

    test('respects trimming of the email', () {
      final result = validateBootstrapInput(
        email: '   ',
        password: 'secret1',
        displayName: 'Ada',
      );
      expect(result, isA<ValidationFailure>());
    });
  });
}
