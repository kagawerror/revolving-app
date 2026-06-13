import '../../../core/money/money.dart';
import '../../companies/domain/fund.dart';

/// Single source of truth for release arithmetic & eligibility, shared by the
/// online release transaction ([computeRelease] in the request repository) and
/// the offline reconcile path (`reconcileRelease` in features/sync). Keeping the
/// math here means a change to "can this fund cover this release, and what is
/// the resulting balance / low flag" happens in exactly one place.

/// Whether [fund] may currently release [amount]: not paused for replenishment
/// AND the balance covers the amount.
bool canReleaseFrom(Fund fund, Money amount) =>
    fund.status != FundStatus.replenishing && fund.canRelease(amount);

/// The balance after deducting [amount] from [fund]. Caller must ensure
/// [canReleaseFrom] first (Money is non-negative; an overdraft would throw).
Money balanceAfterRelease(Fund fund, Money amount) =>
    fund.availableBalance - amount;

/// Whether the post-release [newBalance] is at/under [fund]'s low threshold.
bool isLowAfter(Fund fund, Money newBalance) =>
    newBalance <= fund.lowBalanceThreshold;
