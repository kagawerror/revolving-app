import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';
import '../../companies/domain/fund.dart';

class FundTotals extends Equatable {
  final Money totalBudget;
  final Money totalAvailable;
  final int fundCount;
  final int lowFundCount;
  final int replenishingFundCount;
  final int totalAdjustmentsCentavos;

  const FundTotals({
    required this.totalBudget,
    required this.totalAvailable,
    required this.fundCount,
    required this.lowFundCount,
    required this.replenishingFundCount,
    required this.totalAdjustmentsCentavos,
  });

  /// Budget including all accumulated adjustments — the "Total budget" shown.
  Money get effectiveBudget =>
      Money.fromCentavos(totalBudget.centavos + totalAdjustmentsCentavos);

  /// Cash paid out of the funds (effective budget minus what's still available).
  /// Clamped at >= 0 as a safety net; with adjustments folded into the effective
  /// budget, available should never legitimately exceed it.
  Money get totalDisbursed => Money.fromCentavos(
      (effectiveBudget.centavos - totalAvailable.centavos).clamp(0, 1 << 62));

  /// Fraction 0..1 of the effective budget that is currently disbursed.
  double get utilization => effectiveBudget.centavos == 0
      ? 0.0
      : totalDisbursed.centavos / effectiveBudget.centavos;

  @override
  List<Object?> get props => [
        totalBudget,
        totalAvailable,
        fundCount,
        lowFundCount,
        replenishingFundCount,
        totalAdjustmentsCentavos,
      ];
}

/// Pure aggregate over a company's funds. Admin/CEO "add cash" adjustments are
/// folded into [FundTotals.effectiveBudget] (= budget + adjustments), which is
/// the "Total budget" shown and the basis for disbursed/utilization.
FundTotals computeFundTotals(List<Fund> funds) {
  var budget = Money.zero;
  var available = Money.zero;
  var low = 0;
  var replenishing = 0;
  var adjustments = 0;
  for (final f in funds) {
    budget += f.originalBudget;
    available += f.availableBalance;
    adjustments += f.adjustmentsCentavos;
    if (f.status == FundStatus.low) low++;
    if (f.status == FundStatus.replenishing) replenishing++;
  }
  return FundTotals(
    totalBudget: budget,
    totalAvailable: available,
    fundCount: funds.length,
    lowFundCount: low,
    replenishingFundCount: replenishing,
    totalAdjustmentsCentavos: adjustments,
  );
}

class DashboardSummary extends Equatable {
  final FundTotals totals;
  final int pendingRequestCount;
  final int pendingReplenishmentCount;

  const DashboardSummary({
    required this.totals,
    required this.pendingRequestCount,
    required this.pendingReplenishmentCount,
  });

  @override
  List<Object?> get props => [totals, pendingRequestCount, pendingReplenishmentCount];
}
