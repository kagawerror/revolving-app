import '../../../core/money/money.dart';
import '../../replenishment/domain/replenishment.dart';
import '../../replenishment/domain/replenishment_status.dart';
import '../../requests/domain/fund_request.dart';
import 'report_models.dart';
import 'report_period.dart';

/// Released requests whose effective date falls inside [window], newest-first.
///
/// `effectiveDate = releasedAt ?? createdAt`; a row is [ReleasedRequestRow.datePending]
/// when `releasedAt` is absent (offline-pending / not yet server-confirmed) so
/// it reads honestly with its creation date. Status-agnostic: a request that
/// was released still counts even if it was later acknowledged, disputed, or
/// rolled into a replenishment — the report is about the cash that left the
/// fund in this window, not the request's current lifecycle state. Requests
/// with neither timestamp materialized yet are skipped (nothing to date by).
List<ReleasedRequestRow> releasedRowsInWindow(
  List<FundRequest> all,
  DateRange window,
) {
  final rows = <ReleasedRequestRow>[];
  for (final r in all) {
    final released = r.releasedAt;
    final effective = released ?? r.createdAt;
    if (effective == null) continue;
    if (!window.contains(effective)) continue;
    rows.add(ReleasedRequestRow(
      requestId: r.id,
      beneficiaryName: r.beneficiaryName,
      purpose: r.purpose,
      amount: r.amount,
      effectiveDate: effective,
      datePending: released == null,
    ));
  }
  rows.sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));
  return rows;
}

/// Approved replenishments whose decision date falls inside [window], newest
/// first. Approved-only; date is `decidedAt ?? createdAt`. Records with neither
/// timestamp materialized are skipped.
List<ReplenishmentRow> replenishmentRowsInWindow(
  List<Replenishment> all,
  DateRange window,
) {
  final rows = <ReplenishmentRow>[];
  for (final r in all) {
    if (r.status != ReplenishmentStatus.approved) continue;
    final effective = r.decidedAt ?? r.createdAt;
    if (effective == null) continue;
    if (!window.contains(effective)) continue;
    rows.add(ReplenishmentRow(
      replenishmentId: r.id,
      itemCount: r.itemCount,
      total: r.total,
      approvedDate: r.decidedAt,
      createdDate: r.createdAt,
    ));
  }
  rows.sort((a, b) {
    final ad = a.approvedDate ?? a.createdDate;
    final bd = b.approvedDate ?? b.createdDate;
    if (ad == null || bd == null) return 0;
    return bd.compareTo(ad);
  });
  return rows;
}

/// Sum of [amounts], folding from [Money.zero]. Empty → zero.
Money grandTotal(Iterable<Money> amounts) =>
    amounts.fold(Money.zero, (acc, m) => acc + m);
