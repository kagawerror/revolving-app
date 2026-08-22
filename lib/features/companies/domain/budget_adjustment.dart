import '../../../core/money/money.dart';
import 'fund.dart';

/// Pure outcome of re-setting a fund's original budget. The SAME signed delta
/// (`newBudget - originalBudget`) is applied to the available balance, and the
/// fund status is recomputed against the NEW budget/balance. Unit-testable
/// without Firestore; the transaction in `FirestoreFundRepository.adjustBudget`
/// re-reads the fund and calls this before writing.
class BudgetAdjustment {
  final Money newBudget;
  final Money newBalance;
  final int deltaCentavos;
  final FundStatus newStatus;

  const BudgetAdjustment({
    required this.newBudget,
    required this.newBalance,
    required this.deltaCentavos,
    required this.newStatus,
  });
}

/// Computes the budget/balance/status changes for editing [fund]'s budget to
/// [newBudget]. Throws [StateError] (caught at the data layer and mapped to a
/// `ValidationFailure`) when the edit is illegal:
///   - the new balance would go negative (reduction exceeds available balance);
///   - the budget is unchanged (no-op write).
BudgetAdjustment computeBudgetAdjustment(Fund fund, Money newBudget) {
  if (newBudget == fund.originalBudget) {
    throw StateError('Budget is unchanged.');
  }
  final delta = newBudget.centavos - fund.originalBudget.centavos;
  final newBalanceCentavos = fund.availableBalance.centavos + delta;
  if (newBalanceCentavos < 0) {
    throw StateError('Budget reduction exceeds the available balance.');
  }
  final newBalance = Money.fromCentavos(newBalanceCentavos);

  // Recompute low against the NEW budget/balance (replicates Fund.isLow).
  final low = newBalance <= newBudget.percentageOf(fund.lowBalanceThresholdPct);
  final FundStatus newStatus;
  if (fund.status == FundStatus.replenishing) {
    // A replenishment is in flight; a budget edit must not disturb it.
    newStatus = FundStatus.replenishing;
  } else {
    newStatus = low ? FundStatus.low : FundStatus.active;
  }

  return BudgetAdjustment(
    newBudget: newBudget,
    newBalance: newBalance,
    deltaCentavos: delta,
    newStatus: newStatus,
  );
}
