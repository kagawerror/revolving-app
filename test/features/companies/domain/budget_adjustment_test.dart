import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/budget_adjustment.dart';
import 'package:rev_app/features/companies/domain/fund.dart';

Fund _fund({
  int budget = 10000000, // ₱100,000.00
  int balance = 5000000, // ₱50,000.00
  int thresholdPct = 3,
  FundStatus status = FundStatus.active,
}) =>
    Fund(
      id: 'f1',
      companyId: 'c1',
      name: 'Petty Cash',
      originalBudget: Money.fromCentavos(budget),
      availableBalance: Money.fromCentavos(balance),
      lowBalanceThresholdPct: thresholdPct,
      status: status,
    );

void main() {
  group('computeBudgetAdjustment', () {
    test('increase applies positive delta to budget and balance, stays active',
        () {
      final adj = computeBudgetAdjustment(
        _fund(budget: 10000000, balance: 5000000),
        Money.fromCentavos(12000000),
      );
      expect(adj.deltaCentavos, 2000000);
      expect(adj.newBudget.centavos, 12000000);
      expect(adj.newBalance.centavos, 7000000);
      expect(adj.newStatus, FundStatus.active);
    });

    test('decrease within balance applies negative delta', () {
      final adj = computeBudgetAdjustment(
        _fund(budget: 10000000, balance: 5000000),
        Money.fromCentavos(8000000),
      );
      expect(adj.deltaCentavos, -2000000);
      expect(adj.newBudget.centavos, 8000000);
      expect(adj.newBalance.centavos, 3000000);
      expect(adj.newStatus, FundStatus.active);
    });

    test('decrease exceeding available balance throws StateError', () {
      expect(
        () => computeBudgetAdjustment(
          // balance 50k; reducing budget by 60k would push balance negative
          _fund(budget: 10000000, balance: 5000000),
          Money.fromCentavos(4000000),
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          'Budget reduction exceeds the available balance.',
        )),
      );
    });

    test('decrease to exactly zero balance is allowed', () {
      final adj = computeBudgetAdjustment(
        _fund(budget: 10000000, balance: 5000000),
        Money.fromCentavos(5000000),
      );
      expect(adj.newBalance.centavos, 0);
    });

    test('unchanged budget throws StateError', () {
      expect(
        () => computeBudgetAdjustment(
          _fund(budget: 10000000),
          Money.fromCentavos(10000000),
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          'Budget is unchanged.',
        )),
      );
    });

    test('crossing INTO low recomputes status to low', () {
      // threshold 3% of new budget 10,000,000 = 300,000. New balance 200,000.
      // decrease budget by 800,000 from 10,800,000 → balance 1,000,000 - 800,000.
      final adj = computeBudgetAdjustment(
        _fund(
          budget: 10800000,
          balance: 1000000,
          thresholdPct: 3,
          status: FundStatus.active,
        ),
        Money.fromCentavos(10000000),
      );
      // new balance = 1,000,000 + (-800,000) = 200,000 <= 300,000 → low
      expect(adj.newBalance.centavos, 200000);
      expect(adj.newStatus, FundStatus.low);
    });

    test('crossing OUT of low recomputes status to active', () {
      // currently low: balance 200,000 vs threshold 3% of 10,000,000 = 300,000.
      // increase budget to 20,000,000; balance becomes 200,000 + 10,000,000.
      // new threshold 3% of 20,000,000 = 600,000; balance 10,200,000 > → active.
      final adj = computeBudgetAdjustment(
        _fund(
          budget: 10000000,
          balance: 200000,
          thresholdPct: 3,
          status: FundStatus.low,
        ),
        Money.fromCentavos(20000000),
      );
      expect(adj.newStatus, FundStatus.active);
    });

    test('replenishing status is preserved regardless of low computation', () {
      final adj = computeBudgetAdjustment(
        _fund(
          budget: 10000000,
          balance: 200000,
          thresholdPct: 3,
          status: FundStatus.replenishing,
        ),
        Money.fromCentavos(12000000),
      );
      expect(adj.newStatus, FundStatus.replenishing);
    });
  });
}
