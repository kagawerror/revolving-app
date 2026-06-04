import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';

void main() {
  Fund fund(int balance) => Fund(
        id: 'f1', companyId: 'c1', name: 'PC',
        originalBudget: Money.fromPesos(100000),
        availableBalance: Money.fromCentavos(balance),
        lowBalanceThresholdPct: 3, status: FundStatus.active);

  test('computeRelease deducts and flags low at/under threshold', () {
    final r = computeRelease(fund(500000), Money.fromPesos(2000)); // 5,000 - 2,000 = 3,000
    expect(r.newBalance, Money.fromPesos(3000));
    expect(r.fundIsLow, isTrue); // 3,000 == 3% of 100,000
  });

  test('computeRelease throws when insufficient', () {
    expect(() => computeRelease(fund(100000), Money.fromPesos(2000)),
        throwsStateError);
  });

  test('computeRelease NOT low when balance one centavo above threshold', () {
    // threshold = 3% of 100,000 = 3,000.00 = 300000 centavos.
    // start 500001 centavos, release 2000.00 -> 300001 -> NOT low
    final r = computeRelease(fund(500001), Money.fromPesos(2000));
    expect(r.fundIsLow, isFalse);
  });

  test('computeRelease allows releasing exactly the full balance to zero', () {
    final r = computeRelease(fund(200000), Money.fromCentavos(200000));
    expect(r.newBalance, Money.zero);
    expect(r.fundIsLow, isTrue);
  });

  test('computeRelease throws when fund is replenishing', () {
    final replenishing = Fund(
      id: 'f1', companyId: 'c1', name: 'PC',
      originalBudget: Money.fromPesos(100000),
      availableBalance: Money.fromPesos(50000),
      lowBalanceThresholdPct: 3, status: FundStatus.replenishing);
    expect(() => computeRelease(replenishing, Money.fromPesos(1000)), throwsStateError);
  });
}
