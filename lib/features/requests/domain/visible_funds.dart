import 'package:equatable/equatable.dart';

import '../../auth/domain/app_user.dart';
import '../../companies/domain/fund.dart';

/// Outcome of scoping a candidate fund set down to what a given user may
/// operate on.
///
/// The two booleans deliberately separate "an incharge whose assignment is
/// empty" (the strict empty state — show "No funds assigned") from "a role that
/// isn't scoped at all" (admin/approver/CEO — see everything). Collapsing both
/// into an empty [funds] list would be ambiguous, so [isAssignmentScoped]
/// records whether per-fund scoping was applied.
class VisibleFunds extends Equatable {
  /// The funds the user may see, filtered from the candidates. Input order is
  /// preserved so existing UI ordering (by name) is retained.
  final List<Fund> funds;

  /// True only when assignment scoping was applied (i.e. the user is an
  /// incharge). False for unscoped roles (admin/approver/CEO/employee), whose
  /// [funds] is the untouched candidate list.
  final bool isAssignmentScoped;

  const VisibleFunds({required this.funds, required this.isAssignmentScoped});

  /// The incharge has scoping applied but no funds resolved — render the strict
  /// "No funds assigned" empty state. Never true for an unscoped role.
  bool get isEmptyState => isAssignmentScoped && funds.isEmpty;

  @override
  List<Object?> get props => [funds, isAssignmentScoped];
}

/// Filters [candidateFunds] down to the funds [user] may operate on.
///
/// Contract (see `test/features/requests/domain/visible_funds_test.dart`):
///   * **incharge** (`user.role.canManageFund`): keep only funds whose `id` is
///     in `user.fundAssignments`; `isAssignmentScoped` is true. An empty
///     assignment yields an empty list (→ `isEmptyState`), with NO fallback to
///     all candidate funds. Input order is preserved.
///   * **any other role** (admin/approver/CEO/employee): return the candidates
///     unchanged with `isAssignmentScoped == false`.
///
/// Pure & Firebase-free: callers pass whatever company-scoped stream they
/// already have. Do a Set intersection — do NOT issue a `whereIn` query
/// (10-item cap + needless index); that's a regression.
VisibleFunds resolveVisibleFunds(AppUser user, List<Fund> candidateFunds) {
  if (!user.role.canManageFund) {
    return VisibleFunds(funds: candidateFunds, isAssignmentScoped: false);
  }
  final assigned = user.fundAssignments.toSet();
  final funds =
      candidateFunds.where((f) => assigned.contains(f.id)).toList(growable: false);
  return VisibleFunds(funds: funds, isAssignmentScoped: true);
}
