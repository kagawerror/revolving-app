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
}
