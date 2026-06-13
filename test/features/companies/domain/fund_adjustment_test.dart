import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/companies/domain/fund_adjustment.dart';
import 'package:rev_app/core/money/money.dart';

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
  group('computeFundAdjustment', () {
    test('positive delta raises balance, stays active, budget untouched', () {
      final fund = _fund(budget: 10000000, balance: 5000000);
      final adj = computeFundAdjustment(fund, 2000000);
      expect(adj.signedDeltaCentavos, 2000000);
      expect(adj.newBalance.centavos, 7000000);
      expect(adj.newStatus, FundStatus.active);
      // The outcome exposes no budget field — there is nothing to mutate. The
      // source budget is observably unchanged.
      expect(fund.originalBudget.centavos, 10000000);
    });

    test('deduction within balance applies a negative delta', () {
      final adj = computeFundAdjustment(
        _fund(budget: 10000000, balance: 5000000),
        -2000000,
      );
      expect(adj.signedDeltaCentavos, -2000000);
      expect(adj.newBalance.centavos, 3000000);
      expect(adj.newStatus, FundStatus.active);
    });

    test('deduction crossing the threshold recomputes status to low', () {
      // threshold 3% of UNCHANGED budget 10,000,000 = 300,000.
      // balance 1,000,000 − 800,000 = 200,000 <= 300,000 → low.
      final adj = computeFundAdjustment(
        _fund(budget: 10000000, balance: 1000000, status: FundStatus.active),
        -800000,
      );
      expect(adj.newBalance.centavos, 200000);
      expect(adj.newStatus, FundStatus.low);
    });

    test('addition crossing OUT of low recomputes status to active', () {
      // currently low: balance 200,000 vs threshold 300,000 of budget 10,000,000.
      final adj = computeFundAdjustment(
        _fund(budget: 10000000, balance: 200000, status: FundStatus.low),
        500000,
      );
      expect(adj.newBalance.centavos, 700000);
      expect(adj.newStatus, FundStatus.active);
    });

    test('deduction to exactly zero balance is allowed', () {
      final adj = computeFundAdjustment(
        _fund(budget: 10000000, balance: 5000000),
        -5000000,
      );
      expect(adj.newBalance.centavos, 0);
      // 0 <= threshold 300,000 → low.
      expect(adj.newStatus, FundStatus.low);
    });

    test('deduction below zero throws StateError', () {
      expect(
        () => computeFundAdjustment(
          _fund(budget: 10000000, balance: 5000000),
          -5000001,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          'Deduction exceeds the available balance.',
        )),
      );
    });

    test('zero delta throws StateError', () {
      expect(
        () => computeFundAdjustment(_fund(), 0),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          'Adjustment is zero.',
        )),
      );
    });

    test('replenishing status is preserved regardless of low computation', () {
      final adj = computeFundAdjustment(
        _fund(
          budget: 10000000,
          balance: 200000,
          status: FundStatus.replenishing,
        ),
        500000,
      );
      expect(adj.newStatus, FundStatus.replenishing);
    });
  });
}
