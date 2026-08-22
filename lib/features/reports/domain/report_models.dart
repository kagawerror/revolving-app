import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';
import 'report_period.dart';

/// One released request in the active period window.
@immutable
class ReleasedRequestRow extends Equatable {
  const ReleasedRequestRow({
    required this.requestId,
    required this.beneficiaryName,
    required this.purpose,
    required this.amount,
    required this.effectiveDate,
    required this.datePending,
    required this.fundName,
  });

  final String requestId;
  final String beneficiaryName;
  final String purpose;
  final Money amount;

  /// The name of the fund this release was drawn from, resolved from the fund
  /// doc by id. Empty when the fund is missing/blank/deleted — the report then
  /// groups the row under the `Unassigned` fallback label.
  final String fundName;

  /// The date the row sorts/displays by: the release date when synced, else
  /// `createdAt` for a still-pending release.
  final DateTime effectiveDate;

  /// True while the release is still queued for sync (`releasedAt` absent) — the
  /// row shows a "Pending sync" chip and uses `createdAt` as [effectiveDate].
  final bool datePending;

  @override
  List<Object?> get props => [
    requestId,
    beneficiaryName,
    purpose,
    amount,
    effectiveDate,
    datePending,
    fundName,
  ];
}

/// A set of report detail rows that all belong to the same fund, with their
/// summed [subtotal]. Reports nest detail rows under their fund: the [rows] are
/// the lines for [fundName] (already ordered oldest-first by the grouping fn),
/// and [subtotal] reconciles to the report's grand total when summed across
/// every group. Generic over the row type so released + replenishment-detail
/// share one grouping path.
@immutable
class FundGroup<T> extends Equatable {
  const FundGroup({
    required this.fundName,
    required this.rows,
    required this.subtotal,
  });

  final String fundName;
  final List<T> rows;
  final Money subtotal;

  @override
  List<Object?> get props => [fundName, rows, subtotal];
}

/// One approved (signed-off) replenishment in the active period window.
@immutable
class ReplenishmentRow extends Equatable {
  const ReplenishmentRow({
    required this.replenishmentId,
    required this.itemCount,
    required this.total,
    this.approvedDate,
    this.createdDate,
  });

  final String replenishmentId;
  final int itemCount;
  final Money total;
  final DateTime? approvedDate;
  final DateTime? createdDate;

  @override
  List<Object?> get props => [
    replenishmentId,
    itemCount,
    total,
    approvedDate,
    createdDate,
  ];
}

/// One line of the detailed replenishment export: a single request being
/// replenished within one approved replenishment bundle (full or a partial
/// installment). Joins bundle data (date, amount, partial flag) with the
/// request (beneficiary/purpose) and the fund name.
@immutable
class ReplenishedLineRow extends Equatable {
  const ReplenishedLineRow({
    required this.approvedDate,
    required this.fundName,
    required this.beneficiaryName,
    required this.purpose,
    required this.amount,
    required this.isPartial,
    required this.remarks,
    required this.replenishmentId,
  });

  /// The bundle's `decidedAt ?? createdAt`; null only on legacy un-timestamped
  /// bundles.
  final DateTime? approvedDate;
  final String fundName;
  final String beneficiaryName;
  final String purpose;

  /// The amount credited for this request IN THIS bundle (a partial installment
  /// or the full remainder), not the request's original amount.
  final Money amount;
  final bool isPartial;
  final String remarks;
  final String replenishmentId;

  @override
  List<Object?> get props => [
    approvedDate,
    fundName,
    beneficiaryName,
    purpose,
    amount,
    isPartial,
    remarks,
    replenishmentId,
  ];
}

/// A report payload: the rows for the active window plus the summed grand total
/// and the window the figures belong to (carried through to export headers).
@immutable
class ReportSummary<T> extends Equatable {
  const ReportSummary({
    required this.rows,
    required this.grandTotal,
    required this.period,
    this.truncated = false,
  });

  final List<T> rows;
  final Money grandTotal;
  final ReportPeriod period;

  /// True when the underlying query hit its defensive row cap, so the rows and
  /// [grandTotal] cover only the most recent capped slice of the window rather
  /// than every matching document. The UI surfaces a "showing first N" note so
  /// the total is never silently read as complete.
  final bool truncated;

  @override
  List<Object?> get props => [rows, grandTotal, period, truncated];
}
