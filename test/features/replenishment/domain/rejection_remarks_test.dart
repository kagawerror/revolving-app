import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/replenishment/domain/rejection_remarks.dart';

void main() {
  group('validateRejectionRemarks', () {
    test('rejects an empty string', () {
      expect(validateRejectionRemarks(''), isNotNull);
    });

    test('rejects whitespace-only (trimmed to empty)', () {
      expect(validateRejectionRemarks('     '), isNotNull);
    });

    test('rejects a too-short reason below the minimum length', () {
      final short = 'x' * (kMinRejectionRemarksLength - 1);
      expect(validateRejectionRemarks(short), isNotNull);
    });

    test('whitespace does not pad toward the minimum length', () {
      final padded = '  ${'x' * (kMinRejectionRemarksLength - 1)}  ';
      expect(validateRejectionRemarks(padded), isNotNull);
    });

    test('accepts a reason at exactly the minimum length', () {
      final exact = 'x' * kMinRejectionRemarksLength;
      expect(validateRejectionRemarks(exact), isNull);
    });

    test('accepts a clearly specific reason', () {
      expect(
        validateRejectionRemarks('Amounts do not match the attached receipts.'),
        isNull,
      );
    });
  });
}
