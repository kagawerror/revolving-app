import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/sync/domain/conflict_detection.dart';

void main() {
  group('isOverdraft', () {
    test('amount greater than balance is an overdraft', () {
      expect(
        isOverdraft(Money.fromCentavos(1000), Money.fromCentavos(1001)),
        isTrue,
      );
    });

    test('amount less than balance is not an overdraft', () {
      expect(
        isOverdraft(Money.fromCentavos(1000), Money.fromCentavos(999)),
        isFalse,
      );
    });

    test('exactly-equal balance is NOT an overdraft (boundary)', () {
      expect(
        isOverdraft(Money.fromCentavos(1000), Money.fromCentavos(1000)),
        isFalse,
      );
    });

    test('zero amount against zero balance is not an overdraft', () {
      expect(isOverdraft(Money.zero, Money.zero), isFalse);
    });
  });
}
