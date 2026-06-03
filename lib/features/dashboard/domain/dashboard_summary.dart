import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';
import '../../companies/domain/fund.dart';

class FundTotals extends Equatable {
  final Money totalBudget;
  final Money totalAvailable;
  final int fundCount;
  final int lowFundCount;
  final int replenishingFundCount;

  const FundTotals({
    required this.totalBudget,
    required this.totalAvailable,
    required this.fundCount,
    required this.lowFundCount,
    required this.replenishingFundCount,
  });

  Money get totalDisbursed => totalBudget - totalAvailable;

  /// Fraction 0..1 of the budget that is currently disbursed.
  double get utilization =>
      totalBudget.centavos == 0 ? 0.0 : totalDisbursed.centavos / totalBudget.centavos;

  @override
  List<Object?> get props =>
      [totalBudget, totalAvailable, fundCount, lowFundCount, replenishingFundCount];
}

/// Pure aggregate over a company's funds. (available never exceeds budget, so the
/// disbursed subtraction is always >= 0.)
FundTotals computeFundTotals(List<Fund> funds) {
  var budget = Money.zero;
  var available = Money.zero;
  var low = 0;
  var replenishing = 0;
  for (final f in funds) {
    budget += f.originalBudget;
    available += f.availableBalance;
    if (f.status == FundStatus.low) low++;
    if (f.status == FundStatus.replenishing) replenishing++;
  }
  return FundTotals(
    totalBudget: budget,
    totalAvailable: available,
    fundCount: funds.length,
    lowFundCount: low,
    replenishingFundCount: replenishing,
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
