import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';

void main() {
  test('fromPesos converts to centavos', () {
    expect(Money.fromPesos(100).centavos, 10000);
    expect(Money.fromPesos(0.05).centavos, 5);
  });

  test('addition and subtraction are exact', () {
    final a = Money.fromCentavos(10000);
    final b = Money.fromCentavos(2550);
    expect((a - b).centavos, 7450);
    expect((a + b).centavos, 12550);
  });

  test('percentageOf computes integer-centavo threshold', () {
    // 3% of 100,000.00 = 3,000.00
    expect(Money.fromPesos(100000).percentageOf(3).centavos, 300000);
  });

  test('comparison operators', () {
    expect(Money.fromCentavos(100) <= Money.fromCentavos(100), isTrue);
    expect(Money.fromCentavos(99) < Money.fromCentavos(100), isTrue);
  });

  test('value equality', () {
    expect(Money.fromCentavos(500), Money.fromCentavos(500));
  });

  test('format renders peso string', () {
    expect(Money.fromCentavos(123456).format(), '₱1,234.56');
  });

  test('rejects negative construction', () {
    expect(() => Money.fromCentavos(-1), throwsArgumentError);
  });
}
