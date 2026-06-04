import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/dashboard/domain/dashboard_summary.dart';

Fund _fund(int budget, int available, FundStatus status) => Fund(
      id: 'f', companyId: 'c1', name: 'F',
      originalBudget: Money.fromCentavos(budget),
      availableBalance: Money.fromCentavos(available),
      lowBalanceThresholdPct: 3, status: status);

void main() {
  test('empty funds → zero totals, zero utilization', () {
    final t = computeFundTotals(const []);
    expect(t.totalBudget, Money.zero);
    expect(t.totalAvailable, Money.zero);
    expect(t.totalDisbursed, Money.zero);
    expect(t.utilization, 0.0);
    expect(t.fundCount, 0);
  });

  test('sums budget/available/disbursed and counts statuses', () {
    final t = computeFundTotals([
      _fund(10000000, 4000000, FundStatus.active),    // disbursed 6,000,000
      _fund(5000000, 100000, FundStatus.low),          // disbursed 4,900,000
      _fund(2000000, 2000000, FundStatus.replenishing) // disbursed 0
    ]);
    expect(t.totalBudget, Money.fromCentavos(17000000));
    expect(t.totalAvailable, Money.fromCentavos(6100000));
    expect(t.totalDisbursed, Money.fromCentavos(10900000));
    expect(t.fundCount, 3);
    expect(t.lowFundCount, 1);
    expect(t.replenishingFundCount, 1);
    // utilization = 10,900,000 / 17,000,000
    expect(t.utilization, closeTo(0.6412, 0.0001));
  });
}
