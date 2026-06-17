import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';
import '../../requests/domain/fund_request.dart';
import 'denomination.dart';
import 'denomination_count.dart';

/// Reconciliation result for a cash count.
///
/// `shortage` = the fund is missing cash (counted less than it should hold),
/// `overage`  = there is more cash than expected, `balanced` = exact match.
enum AuditVerdict { balanced, shortage, overage }

/// Immutable outcome of reconciling a physical cash count against the fund's
/// expected on-hand cash: `effectiveBudget − physicalCash − outstanding`.
///
/// [varianceCentavos] is a SIGNED raw int (positive = shortage, negative =
/// overage, 0 = balanced) — deliberately a plain int and never a [Money], which
/// cannot hold a negative value.
class FundAuditOutcome extends Equatable {
  final Money effectiveBudget;
  final Money physicalCash;
  final Money outstanding;
  final int varianceCentavos;
  final List<DenominationCount> denominations;

  const FundAuditOutcome({
    required this.effectiveBudget,
    required this.physicalCash,
    required this.outstanding,
    required this.varianceCentavos,
    required this.denominations,
  });

  AuditVerdict get verdict {
    if (varianceCentavos > 0) return AuditVerdict.shortage;
    if (varianceCentavos < 0) return AuditVerdict.overage;
    return AuditVerdict.balanced;
  }

  @override
  List<Object?> get props => [
        effectiveBudget,
        physicalCash,
        outstanding,
        varianceCentavos,
        denominations,
      ];
}

/// Sum of every counted denomination, in integer centavos. Missing or zero-count
/// rows contribute nothing. Empty map → [Money.zero].
Money sumDenominations(Map<Denomination, int> counts) {
  var total = 0;
  for (final entry in counts.entries) {
    total += entry.key.centavos * entry.value;
  }
  return Money.fromCentavos(total);
}

/// Total cash still out of the fund for the given requests — the sum of each
/// request's outstanding [FundRequest.remaining], clamped to ≥ 0 per request so a
/// stray negative never reduces the total. Caller pre-filters to the fund and to
/// outstanding statuses; this guards regardless.
Money outstandingReleasedCash(Iterable<FundRequest> forFund) {
  var total = 0;
  for (final r in forFund) {
    final c = r.remaining.centavos;
    total += c < 0 ? 0 : c;
  }
  return Money.fromCentavos(total);
}

/// Reconcile a physical cash count against expected on-hand cash.
///
/// expected on-hand = `effectiveBudget − outstanding`
/// variance         = `expected − physicalCash`
///                  = `effectiveBudget − physicalCash − outstanding`  (signed int)
///
/// All arithmetic is on raw centavos so the variance can be negative (overage)
/// without ever constructing a negative [Money].
FundAuditOutcome computeFundAudit({
  required Money effectiveBudget,
  required Map<Denomination, int> counts,
  required Iterable<FundRequest> outstandingForFund,
}) {
  final physicalCash = sumDenominations(counts);
  final outstanding = outstandingReleasedCash(outstandingForFund);
  final variance =
      effectiveBudget.centavos - physicalCash.centavos - outstanding.centavos;

  final denominations = [
    for (final d in kDenominationsDescending)
      DenominationCount(denomination: d, count: counts[d] ?? 0),
  ];

  return FundAuditOutcome(
    effectiveBudget: effectiveBudget,
    physicalCash: physicalCash,
    outstanding: outstanding,
    varianceCentavos: variance,
    denominations: denominations,
  );
}
