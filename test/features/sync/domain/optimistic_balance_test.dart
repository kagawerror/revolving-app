import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/sync/domain/optimistic_balance.dart';
import 'package:rev_app/features/sync/domain/release_intent.dart';

ReleaseIntent _intent(int amount, {String cid = 'c'}) => ReleaseIntent(
      requestId: 'r-$cid',
      fundId: 'f1',
      companyId: 'c1',
      amount: Money.fromCentavos(amount),
      clientReleaseId: cid,
    );

void main() {
  group('optimisticBalance', () {
    test('no pending releases → equals server balance', () {
      final b = optimisticBalance(Money.fromCentavos(5000), const []);
      expect(b.centavos, 5000);
      expect(b.isNegative, isFalse);
    });

    test('subtracts the sum of pending releases', () {
      final b = optimisticBalance(
        Money.fromCentavos(10000),
        [_intent(3000, cid: 'a'), _intent(2500, cid: 'b')],
      );
      expect(b.centavos, 4500);
    });

    test('may go negative (over-commitment) and is NOT clamped', () {
      final b = optimisticBalance(
        Money.fromCentavos(5000),
        [_intent(3000, cid: 'a'), _intent(4000, cid: 'b')],
      );
      expect(b.centavos, -2000);
      expect(b.isNegative, isTrue);
    });

    test('exactly drained to zero', () {
      final b = optimisticBalance(
        Money.fromCentavos(5000),
        [_intent(5000, cid: 'a')],
      );
      expect(b.centavos, 0);
      expect(b.isNegative, isFalse);
    });
  });
}
