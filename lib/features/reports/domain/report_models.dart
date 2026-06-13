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
  });

  final String requestId;
  final String beneficiaryName;
  final String purpose;
  final Money amount;

  /// The date the row sorts/displays by: the release date when synced, else
  /// `createdAt` for a still-pending release.
  final DateTime effectiveDate;

  /// True while the release is still queued for sync (`releasedAt` absent) — the
  /// row shows a "Pending sync" chip and uses `createdAt` as [effectiveDate].
  final bool datePending;

  @override
  List<Object?> get props =>
      [requestId, beneficiaryName, purpose, amount, effectiveDate, datePending];
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
  List<Object?> get props =>
      [replenishmentId, itemCount, total, approvedDate, createdDate];
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
