import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';
import 'fund_request.dart';

/// Immutable view-model for a request's amount breakdown:
/// original − approved partial − pending partial → projected remaining.
///
/// Authoritative field names: the [RequestBreakdownView] widget renders this.
/// Kept dumb on purpose — no derivation, just the four already-computed amounts
/// plus convenience predicates the view branches on. Build it via
/// [computeRequestBreakdown].
class RequestBreakdown extends Equatable {
  const RequestBreakdown({
    required this.original,
    required this.approvedPartial,
    required this.pendingPartial,
    required this.projectedRemaining,
  });

  /// `request.amount` — the full sanctioned amount.
  final Money original;

  /// Already-approved partial total (`request.replenished`).
  final Money approvedPartial;

  /// Submitted-but-not-yet-approved partial total ("for approval").
  final Money pendingPartial;

  /// `original − approvedPartial − pendingPartial`, floored at zero.
  final Money projectedRemaining;

  bool get hasApproved => approvedPartial.centavos > 0;
  bool get hasPending => pendingPartial.centavos > 0;
  bool get hasAnyPartial => hasApproved || hasPending;

  @override
  List<Object?> get props =>
      [original, approvedPartial, pendingPartial, projectedRemaining];
}

/// Pure decision function (testable seam, like `computeRelease`).
///
/// - `approvedPartial` = `request.replenished` (cumulative approved).
/// - `pendingPartial` = sum of submitted-but-not-approved replenishment amounts
///   for this request, supplied by the caller.
/// - `projectedRemaining` = original − approved − pending, floored at zero
///   centavos (never negative, even if approved + pending exceed original).
RequestBreakdown computeRequestBreakdown(
  FundRequest request, {
  required Money pendingPartial,
}) {
  final original = request.amount;
  final approved = request.replenished;
  final consumed = approved.centavos + pendingPartial.centavos;
  final remainingCentavos = original.centavos - consumed;
  return RequestBreakdown(
    original: original,
    approvedPartial: approved,
    pendingPartial: pendingPartial,
    projectedRemaining:
        Money.fromCentavos(remainingCentavos < 0 ? 0 : remainingCentavos),
  );
}
