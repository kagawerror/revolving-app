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
  DateRange window, {
  Map<String, String> fundNameById = const {},
}) {
  final rows = <ReleasedRequestRow>[];
  for (final r in all) {
    final released = r.releasedAt;
    final effective = released ?? r.createdAt;
    if (effective == null) continue;
    if (!window.contains(effective)) continue;
    rows.add(
      ReleasedRequestRow(
        requestId: r.id,
        beneficiaryName: r.beneficiaryName,
        purpose: r.purpose,
        amount: r.amount,
        effectiveDate: effective,
        datePending: released == null,
        fundName: fundNameById[r.fundId] ?? '',
      ),
    );
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
    rows.add(
      ReplenishmentRow(
        replenishmentId: r.id,
        itemCount: r.itemCount,
        total: r.total,
        approvedDate: r.decidedAt,
        createdDate: r.createdAt,
      ),
    );
  }
  rows.sort((a, b) {
    final ad = a.approvedDate ?? a.createdDate;
    final bd = b.approvedDate ?? b.createdDate;
    if (ad == null || bd == null) return 0;
    return bd.compareTo(ad);
  });
  return rows;
}

/// Flattens approved replenishment bundles into per-request detail rows: one
/// row per `(bundle, item)`, enriched with the request's beneficiary/purpose
/// (from [requestById]) and the bundle's fund name (from [fundNameById]). Items
/// whose request is missing from [requestById] are skipped defensively (e.g. a
/// deleted request). Sorted newest-approved first, then fund, then beneficiary.
///
/// Caller supplies bundles already filtered to the window + approved (e.g. from
/// `fetchApprovedReplenishments`); this fn does no date filtering.
List<ReplenishedLineRow> replenishmentLineRows(
  List<Replenishment> approved,
  Map<String, FundRequest> requestById,
  Map<String, String> fundNameById,
) {
  final rows = <ReplenishedLineRow>[];
  for (final rep in approved) {
    final date = rep.decidedAt ?? rep.createdAt;
    final fundName = fundNameById[rep.fundId] ?? '';
    for (final item in rep.items) {
      final req = requestById[item.requestId];
      if (req == null) continue;
      rows.add(
        ReplenishedLineRow(
          approvedDate: date,
          fundName: fundName,
          beneficiaryName: req.beneficiaryName,
          purpose: req.purpose,
          amount: item.amount,
          isPartial: item.isPartial,
          remarks: item.remarks,
          replenishmentId: rep.id,
        ),
      );
    }
  }
  rows.sort((a, b) {
    final ad = a.approvedDate, bd = b.approvedDate;
    final byDate = (ad == null || bd == null) ? 0 : bd.compareTo(ad);
    if (byDate != 0) return byDate;
    final byFund = a.fundName.compareTo(b.fundName);
    if (byFund != 0) return byFund;
    return a.beneficiaryName.compareTo(b.beneficiaryName);
  });
  return rows;
}

/// Sum of [amounts], folding from [Money.zero]. Empty → zero.
Money grandTotal(Iterable<Money> amounts) =>
    amounts.fold(Money.zero, (acc, m) => acc + m);

/// Buckets [rows] by their fund name into [FundGroup]s for nested report
/// rendering. Pure: the four accessors read the fund name, amount, and (sort)
/// date off a row of any type so released + replenishment-detail share one path.
///
/// Rules:
/// - A row whose [fundNameOf] is empty (after trim) groups under
///   [fallbackFundName] (default `Unassigned`).
/// - Within a group, rows sort by [dateOf] OLDEST-first; null dates sort last,
///   preserving input order among themselves (stable).
/// - Each group's `subtotal` is `grandTotal` over its rows' amounts.
/// - Groups are returned A→Z by fund name, case-insensitive; the fallback label
///   sorts naturally among the real names.
/// - Empty input → empty list.
List<FundGroup<T>> groupByFund<T>(
  List<T> rows,
  String Function(T) fundNameOf,
  Money Function(T) amountOf,
  DateTime? Function(T) dateOf, {
  String fallbackFundName = 'Unassigned',
}) {
  // Preserve first-seen order so the stable in-bucket sort is deterministic.
  final buckets = <String, List<T>>{};
  for (final r in rows) {
    final raw = fundNameOf(r).trim();
    final name = raw.isEmpty ? fallbackFundName : raw;
    (buckets[name] ??= <T>[]).add(r);
  }

  final groups = <FundGroup<T>>[];
  for (final entry in buckets.entries) {
    // Decorate-sort-undecorate so equal (Equatable) rows can't collide on a
    // map key: the original index is the stable tiebreaker for null/equal dates.
    final decorated = [
      for (var i = 0; i < entry.value.length; i++) (i, entry.value[i]),
    ];
    decorated.sort((a, b) {
      final da = dateOf(a.$2), db = dateOf(b.$2);
      if (da == null && db == null) return a.$1.compareTo(b.$1);
      if (da == null) return 1;
      if (db == null) return -1;
      final byDate = da.compareTo(db);
      return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
    });
    final bucket = [for (final d in decorated) d.$2];
    groups.add(
      FundGroup<T>(
        fundName: entry.key,
        rows: bucket,
        subtotal: grandTotal(bucket.map(amountOf)),
      ),
    );
  }

  groups.sort(
    (a, b) => a.fundName.toLowerCase().compareTo(b.fundName.toLowerCase()),
  );
  return groups;
}
