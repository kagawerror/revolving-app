import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/fund.dart';

void main() {
  Fund fund({int balance = 10000000, int budget = 10000000, int pct = 3}) => Fund(
        id: 'f1',
        companyId: 'c1',
        name: 'Petty Cash',
        originalBudget: Money.fromCentavos(budget),
        availableBalance: Money.fromCentavos(balance),
        lowBalanceThresholdPct: pct,
        status: FundStatus.active,
      );

  test('threshold is pct of original budget', () {
    // 3% of 100,000.00 = 3,000.00
    expect(fund().lowBalanceThreshold, Money.fromPesos(3000));
  });

  test('isLow when balance <= threshold', () {
    expect(fund(balance: 300000).isLow, isTrue); // exactly 3,000.00
    expect(fund(balance: 300001).isLow, isFalse);
  });

  test('canRelease only when balance covers amount', () {
    expect(fund(balance: 500000).canRelease(Money.fromPesos(5000)), isTrue);
    expect(fund(balance: 499999).canRelease(Money.fromPesos(5000)), isFalse);
  });

  test('canRelease true when balance exactly equals amount', () {
    expect(fund(balance: 500000).canRelease(Money.fromPesos(5000)), isTrue);
  });

  test('FundStatus.fromName round-trips and defaults to active', () {
    expect(FundStatus.fromName('low'), FundStatus.low);
    expect(FundStatus.fromName('replenishing'), FundStatus.replenishing);
    expect(FundStatus.fromName('garbage'), FundStatus.active);
    expect(FundStatus.fromName(null), FundStatus.active);
  });

  test('fromMap parses centavos/status; toCreateMap omits id and seeds fields', () {
    final f = Fund.fromMap('f9', {
      'companyId': 'c1', 'name': 'PC',
      'originalBudgetCentavos': 10000000,
      'availableBalanceCentavos': 9500000,
      'lowBalanceThresholdPct': 5, 'status': 'low',
    });
    expect(f.id, 'f9');
    expect(f.availableBalance, Money.fromCentavos(9500000));
    expect(f.status, FundStatus.low);
    final map = f.toCreateMap();
    expect(map.containsKey('id'), isFalse);
    expect(map['originalBudgetCentavos'], 10000000);
  });
}
