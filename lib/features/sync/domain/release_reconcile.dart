import '../../../core/money/money.dart';
import '../../companies/domain/fund.dart';
import '../../requests/domain/release_math.dart';
import 'release_intent.dart';

/// Outcome of reconciling a queued [ReleaseIntent] against current server state.
sealed class ReconcileDecision {
  const ReconcileDecision();
}

/// The release is valid against the server: deduct and record [newBalance].
/// [fundIsLow] flags whether the fund crossed its low threshold.
class ReconcileApplied extends ReconcileDecision {
  final Money newBalance;
  final bool fundIsLow;
  const ReconcileApplied(this.newBalance, this.fundIsLow);

  @override
  bool operator ==(Object other) =>
      other is ReconcileApplied &&
      other.newBalance == newBalance &&
      other.fundIsLow == fundIsLow;

  @override
  int get hashCode => Object.hash(newBalance, fundIsLow);
}

/// The server already applied this exact release (matched by clientReleaseId).
/// Replaying it must be a no-op — do NOT deduct again (idempotency).
class ReconcileAlreadyApplied extends ReconcileDecision {
  const ReconcileAlreadyApplied();

  @override
  bool operator ==(Object other) => other is ReconcileAlreadyApplied;

  @override
  int get hashCode => 0;
}

/// The fund can no longer cover the release (another device drained it, or the
/// fund is replenishing). The request must land in `conflict` for the incharge.
class ReconcileConflictInsufficient extends ReconcileDecision {
  const ReconcileConflictInsufficient();

  @override
  bool operator ==(Object other) => other is ReconcileConflictInsufficient;

  @override
  int get hashCode => 1;
}

/// Decide what to do with a queued release [intent] given the current
/// [serverFund]. Pure — the eligibility/arithmetic comes from release_math so it
/// stays identical to the online `computeRelease`.
///
/// - [alreadyApplied] true (server has this clientReleaseId) → no-op for
///   idempotency, regardless of balance.
/// - else if the fund can't cover it (insufficient, or replenishing) →
///   conflictInsufficient.
/// - else → applied with the new balance and low flag.
ReconcileDecision reconcileRelease(
  Fund serverFund,
  ReleaseIntent intent, {
  required bool alreadyApplied,
}) {
  if (alreadyApplied) return const ReconcileAlreadyApplied();
  if (!canReleaseFrom(serverFund, intent.amount)) {
    return const ReconcileConflictInsufficient();
  }
  final newBalance = balanceAfterRelease(serverFund, intent.amount);
  return ReconcileApplied(newBalance, isLowAfter(serverFund, newBalance));
}
