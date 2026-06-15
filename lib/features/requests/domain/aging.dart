import 'package:equatable/equatable.dart';

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
