import '../../../core/money/money.dart';
import 'release_intent.dart';

/// The balance to DISPLAY while one or more local releases are still pending
/// sync: the server balance minus the sum of pending local release amounts for
/// that fund.
///
/// This is an OPTIMISTIC display value. It may go below zero (e.g. two devices
/// each released against the same balance) — we deliberately do NOT clamp it,
/// so the UI can surface the over-commitment to the incharge rather than hiding
/// it. The authoritative balance is always the server's; this is presentation
/// only. Because Money is non-negative, the math is done in raw centavos and the
/// result is returned as a signed-aware Money only when non-negative; a negative
/// optimistic total is represented by returning [_negative] semantics via the
/// signed centavos in the returned record.
class OptimisticBalance {
  /// Signed centavos — may be negative to express over-commitment.
  final int centavos;
  const OptimisticBalance(this.centavos);

  bool get isNegative => centavos < 0;

  @override
  bool operator ==(Object other) =>
      other is OptimisticBalance && other.centavos == centavos;

  @override
  int get hashCode => centavos.hashCode;

  @override
  String toString() => 'OptimisticBalance($centavos)';
}

/// Optimistic display balance = serverBalance − Σ pending local release amounts.
/// Returns signed centavos (may be negative — not clamped, see class doc).
OptimisticBalance optimisticBalance(
  Money serverBalance,
  Iterable<ReleaseIntent> pendingLocalReleasesForFund,
) {
  var total = serverBalance.centavos;
  for (final intent in pendingLocalReleasesForFund) {
    total -= intent.amount.centavos;
  }
  return OptimisticBalance(total);
}
