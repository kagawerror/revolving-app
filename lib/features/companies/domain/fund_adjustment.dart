import '../../../core/money/money.dart';
import 'fund.dart';

/// Pure outcome of an availability-only fund adjustment. A signed centavo delta
/// is applied to the available balance ONLY — the original budget and the
/// low-balance threshold are NEVER changed. The status is recomputed against the
/// UNCHANGED budget. Unit-testable without Firestore; the transaction in
/// `FirestoreFundRepository.adjustBalance` re-reads the fund and calls this
/// before writing.
class FundAdjustment {
  final Money newBalance;
  final int signedDeltaCentavos;
  final FundStatus newStatus;

  const FundAdjustment({
    required this.newBalance,
    required this.signedDeltaCentavos,
    required this.newStatus,
  });
}

/// Computes the balance/status change for applying [signedDeltaCentavos] to
/// [fund]'s available balance. Throws [StateError] (caught at the data layer and
/// mapped to a `ValidationFailure`) when the adjustment is illegal:
///   - the delta is zero (no-op write);
///   - the deduction would push the balance below ₱0.
///
/// The budget is intentionally untouched: there is no budget field on the
/// outcome. Status is recomputed against `fund.lowBalanceThreshold` (derived
/// from the UNCHANGED budget); a fund in flight (`replenishing`) keeps that
/// status so an adjustment cannot disturb a pending replenishment.
FundAdjustment computeFundAdjustment(Fund fund, int signedDeltaCentavos) {
  if (signedDeltaCentavos == 0) {
    throw StateError('Adjustment is zero.');
  }
  final newBalanceCentavos =
      fund.availableBalance.centavos + signedDeltaCentavos;
  if (newBalanceCentavos < 0) {
    throw StateError('Deduction exceeds the available balance.');
  }
  final newBalance = Money.fromCentavos(newBalanceCentavos);

  // Recompute low against the UNCHANGED budget threshold (replicates Fund.isLow).
  final low = newBalance <= fund.lowBalanceThreshold;
  final FundStatus newStatus;
  if (fund.status == FundStatus.replenishing) {
    newStatus = FundStatus.replenishing;
  } else {
    newStatus = low ? FundStatus.low : FundStatus.active;
  }

  return FundAdjustment(
    newBalance: newBalance,
    signedDeltaCentavos: signedDeltaCentavos,
    newStatus: newStatus,
  );
}
