import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';
import 'replenishment.dart';
import 'replenishment_status.dart';

/// How a single liquidation line stands right now. Mirrors the subset of
/// [ReplenishmentStatus] that a request's owner cares about — a `draft` report
/// is not a liquidation event at all, so it has no representation here.
enum LiquidationEntryStatus { approved, forApproval, rejected }

/// One replenishment-report LINE ITEM that liquidated (part of) a request.
///
/// This is the itemized counterpart of the lumped `approvedPartial` /
/// `pendingPartial` totals on `RequestBreakdown`: instead of "₱X approved",
/// the request detail can show each report that contributed, when, and in what
/// state. Read-only — nothing here mutates money.
class LiquidationEntry extends Equatable {
  const LiquidationEntry({
    required this.replenishmentId,
    required this.date,
    required this.isPartial,
    required this.amount,
    required this.status,
    this.remarks = '',
  });

  final String replenishmentId;

  /// Report date: `submittedAt ?? decidedAt ?? createdAt`. Nullable because
  /// legacy docs predate those timestamps — render "—", never crash.
  final DateTime? date;

  final bool isPartial;

  /// Line-item amount in centavos (never a `double`).
  final Money amount;

  final LiquidationEntryStatus status;
  final String remarks;

  bool get isApproved => status == LiquidationEntryStatus.approved;

  @override
  List<Object?> get props =>
      [replenishmentId, date, isPartial, amount, status, remarks];
}

/// Flattens [replenishments] into the itemized liquidation history of
/// [requestId], oldest-first. Pure — no I/O — and the unit-test seam for the
/// full request-breakdown variant, mirroring `computeRequestBreakdown` /
/// `partialAmountByRequest`.
///
/// * `draft` reports are always skipped (no money has moved).
/// * `rejected` reports are skipped unless [includeRejected].
/// * FULL items of a `submitted` report are skipped, mirroring
///   `partialAmountByRequest` exactly. That function feeds the breakdown's
///   `pendingPartial`, which `projectedRemaining` subtracts — so emitting a
///   pending full row here would render a debit the Remaining line never
///   accounted for, i.e. `Original − Σ(rows) ≠ Remaining`. Approved full items
///   DO bump `replenishedCentavos` server-side, so they reconcile against
///   `approvedPartial` and are kept (as are rejected ones, which are
///   opt-in history rather than ledger arithmetic).
/// * One entry per matching `items[]` element — duplicates are NOT merged, so
///   the list reads as a ledger.
/// * A report tagged with [requestId] but carrying no matching line item
///   (legacy doc) contributes nothing.
/// * Ordering: ascending date, null dates last, ties broken by
///   `replenishmentId` then by the report's own item order (deterministic).
List<LiquidationEntry> computeLiquidationHistory(
  String requestId,
  Iterable<Replenishment> replenishments, {
  bool includeRejected = false,
}) {
  // (entry, tie-break index) pairs — List.sort is not stable, so the source
  // order is carried explicitly to keep duplicate items in report order.
  final acc = <(LiquidationEntry, int)>[];
  var seq = 0;

  for (final rep in replenishments) {
    final status = _entryStatusOf(rep.status);
    if (status == null) continue; // draft
    if (status == LiquidationEntryStatus.rejected && !includeRejected) continue;

    final date = rep.submittedAt ?? rep.decidedAt ?? rep.createdAt;
    for (final item in rep.items) {
      if (item.requestId != requestId) continue;
      // Ledger arithmetic guard — see the doc comment above.
      if (status == LiquidationEntryStatus.forApproval && !item.isPartial) {
        continue;
      }
      acc.add((
        LiquidationEntry(
          replenishmentId: rep.id,
          date: date,
          isPartial: item.isPartial,
          amount: item.amount,
          status: status,
          remarks: item.remarks,
        ),
        seq++,
      ));
    }
  }

  acc.sort((a, b) {
    final byDate = _compareDates(a.$1.date, b.$1.date);
    if (byDate != 0) return byDate;
    final byId = a.$1.replenishmentId.compareTo(b.$1.replenishmentId);
    if (byId != 0) return byId;
    return a.$2.compareTo(b.$2);
  });

  return [for (final e in acc) e.$1];
}

/// `null` means "not a liquidation event" (a draft report).
LiquidationEntryStatus? _entryStatusOf(ReplenishmentStatus status) =>
    switch (status) {
      ReplenishmentStatus.approved => LiquidationEntryStatus.approved,
      ReplenishmentStatus.submitted => LiquidationEntryStatus.forApproval,
      ReplenishmentStatus.rejected => LiquidationEntryStatus.rejected,
      ReplenishmentStatus.draft => null,
    };

/// Ascending, with undated (legacy) reports sorted last rather than first.
int _compareDates(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}
