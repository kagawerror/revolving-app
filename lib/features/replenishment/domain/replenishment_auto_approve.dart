import '../../../core/money/money.dart';
import '../../companies/domain/fund.dart';
import 'replenishment.dart';
import 'replenishment_status.dart';

/// Pure outcome of crediting a replenishment back onto a fund, mirroring
/// `computeRelease` / `release_math`. Decouples the money arithmetic (and the
/// resulting fund status) from the Firestore transaction so it can be unit
/// tested directly.
class AutoApproveOutcome {
  /// Fund balance AFTER adding the replenishment total back.
  final Money newBalance;

  /// Fund status derived from [newBalance]: `low` at/under the threshold, else
  /// `active`. Never `replenishing` — crediting ends the replenishment.
  final FundStatus newStatus;

  const AutoApproveOutcome({required this.newBalance, required this.newStatus});
}

/// Credits [total] back onto [fund] and derives the restored fund status from
/// the new balance. Single source of truth shared by the auto-approve submit
/// transaction; the SAME balance->status rule the repository uses on
/// approve/reject/discard (`fund.isLow ? low : active`).
AutoApproveOutcome computeAutoApprove(Fund fund, Money total) {
  final newBalance = fund.availableBalance + total;
  final credited = Fund(
    id: fund.id,
    companyId: fund.companyId,
    name: fund.name,
    originalBudget: fund.originalBudget,
    availableBalance: newBalance,
    lowBalanceThresholdPct: fund.lowBalanceThresholdPct,
    status: fund.status,
    adjustmentsCentavos: fund.adjustmentsCentavos,
  );
  return AutoApproveOutcome(
    newBalance: newBalance,
    newStatus: credited.isLow ? FundStatus.low : FundStatus.active,
  );
}

/// Whether [r] is an auto-approved report still awaiting an approver's
/// acknowledgment. Equivalent to [Replenishment.needsAcknowledgment]; exposed
/// as a free function for the presentation gate + unit testing.
bool canAcknowledge(Replenishment r) =>
    r.status == ReplenishmentStatus.approved &&
    (r.autoApproved ?? false) &&
    r.acknowledgedByUid == null;
