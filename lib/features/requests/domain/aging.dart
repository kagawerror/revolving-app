import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';
import '../../companies/domain/company.dart';
import 'fund_request.dart';

/// Aging severity for an outstanding (released/acknowledged/disputed)
/// not-yet-replenished request, by calendar days outstanding. Pure mapping; the
/// presentation layer maps these onto the shared status palette.
enum AgingBucket { green, amber, red }

/// Whole calendar days between [createdAt] and [today], ignoring time-of-day:
/// both are floored to their date before subtracting, so 23:59 → next-day 00:01
/// counts as one day. A future [createdAt] clamps to 0 rather than going
/// negative.
int agingDays(DateTime createdAt, DateTime today) {
  final from = DateTime(createdAt.year, createdAt.month, createdAt.day);
  final to = DateTime(today.year, today.month, today.day);
  final days = to.difference(from).inDays;
  return days < 0 ? 0 : days;
}

/// 0–30 green, 31–60 amber, 61+ red.
AgingBucket bucketFor(int days) {
  if (days <= 30) return AgingBucket.green;
  if (days <= 60) return AgingBucket.amber;
  return AgingBucket.red;
}

/// A/R aging bracket for GROUPED day-bracket sections. Distinct from
/// [AgingBucket] (the 3-tone per-row chip severity); these 4 finance brackets
/// drive section grouping only and never touch chip color.
enum AgingBracket { d1to30, d31to60, d61to90, d90plus }

/// Day 0 (released today) and 1..30 → d1to30; 90+ is the catch-all.
AgingBracket bracketFor4(int days) {
  if (days <= 30) return AgingBracket.d1to30;
  if (days <= 60) return AgingBracket.d31to60;
  if (days <= 90) return AgingBracket.d61to90;
  return AgingBracket.d90plus;
}

/// "1–30 days" / "31–60 days" / "61–90 days" / "90+ days" (en-dash U+2013).
String bracketLabel(AgingBracket b) {
  switch (b) {
    case AgingBracket.d1to30:
      return '1–30 days';
    case AgingBracket.d31to60:
      return '31–60 days';
    case AgingBracket.d61to90:
      return '61–90 days';
    case AgingBracket.d90plus:
      return '90+ days';
  }
}

/// One day-bracket section of outstanding requests, with a precomputed
/// integer-centavo [total].
class DayBracketGroup extends Equatable {
  final AgingBracket bracket;
  final List<FundRequest> requests;
  final Money total;
  const DayBracketGroup({
    required this.bracket,
    required this.requests,
    required this.total,
  });

  int get count => requests.length;

  @override
  List<Object?> get props => [bracket, requests, total];
}

/// Pure summation seam — folds amounts as integer centavos via Money.+.
Money sumAmounts(Iterable<FundRequest> requests) =>
    requests.fold(Money.zero, (acc, r) => acc + r.amount);

/// Folds [requests] into [DayBracketGroup]s, most-stale-first
/// ([d90plus, d61to90, d31to60, d1to30]), skipping empty brackets. Request
/// order within a bracket is preserved (insertion order). A null createdAt
/// counts as 0 days → d1to30.
List<DayBracketGroup> groupByDayBracket(
  List<FundRequest> requests,
  DateTime today,
) {
  final byBracket = <AgingBracket, List<FundRequest>>{};

  for (final r in requests) {
    final days = r.createdAt == null ? 0 : agingDays(r.createdAt!, today);
    final bracket = bracketFor4(days);
    (byBracket[bracket] ??= <FundRequest>[]).add(r);
  }

  // Fixed most-stale-first emission order; empty brackets are skipped.
  const order = [
    AgingBracket.d90plus,
    AgingBracket.d61to90,
    AgingBracket.d31to60,
    AgingBracket.d1to30,
  ];

  return [
    for (final bracket in order)
      if (byBracket[bracket] case final list?)
        DayBracketGroup(
          bracket: bracket,
          requests: list,
          total: sumAmounts(list),
        ),
  ];
}

/// One company's outstanding requests, for the admin grouped aging view.
class AgingGroup extends Equatable {
  final Company company;
  final List<FundRequest> requests;
  const AgingGroup({required this.company, required this.requests});

  @override
  List<Object?> get props => [company, requests];
}

/// Synthetic company used when an outstanding request's companyId matches no
/// known company (e.g. a deleted company). Such requests are bucketed together
/// and rendered last so they're never silently dropped.
const _unknownCompany = Company(id: '', name: 'Unknown company');

/// Folds [outstanding] requests into one [AgingGroup] per company that actually
/// has outstanding requests, sorted by company name (case-insensitive).
/// Companies with zero outstanding requests are skipped. Requests whose
/// companyId matches no company are collected into a single synthetic "Unknown
/// company" group placed LAST. Request order within each group is preserved
/// (callers pass createdAt-DESC).
List<AgingGroup> groupOutstandingByCompany(
  List<Company> companies,
  List<FundRequest> outstanding,
) {
  final byId = {for (final c in companies) c.id: c};

  // Dart maps preserve insertion order, so requests within each company keep
  // their incoming (createdAt-DESC) order.
  final known = <String, List<FundRequest>>{};
  final orphans = <FundRequest>[];

  for (final r in outstanding) {
    if (byId.containsKey(r.companyId)) {
      (known[r.companyId] ??= <FundRequest>[]).add(r);
    } else {
      orphans.add(r);
    }
  }

  final groups = known.entries
      .map((e) => AgingGroup(company: byId[e.key]!, requests: e.value))
      .toList()
    ..sort((a, b) =>
        a.company.name.toLowerCase().compareTo(b.company.name.toLowerCase()));

  if (orphans.isNotEmpty) {
    groups.add(AgingGroup(company: _unknownCompany, requests: orphans));
  }
  return groups;
}
