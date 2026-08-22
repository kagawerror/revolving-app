import '../domain/company.dart';
import '../domain/fund.dart';

/// Sentinel label for funds whose [Fund.companyId] has no matching [Company].
const String _unknownCompany = 'Unknown company';

/// Groups [funds] by their owning company, joining in company names.
///
/// Pure and order-stable: funds are assumed pre-sorted by name (the query does
/// `orderBy('name')`), so each group preserves input order. Groups are sorted by
/// company name (case-insensitive) with the `'Unknown company'` bucket last.
/// Companies with no funds are omitted entirely.
List<({String companyId, String companyName, List<Fund> funds})>
groupFundsByCompany(List<Fund> funds, List<Company> companies) {
  final names = {for (final c in companies) c.id: c.name};

  // Preserve first-seen order of companyIds so funds stay name-sorted.
  final order = <String>[];
  final byCompany = <String, List<Fund>>{};
  for (final fund in funds) {
    final list = byCompany.putIfAbsent(fund.companyId, () {
      order.add(fund.companyId);
      return <Fund>[];
    });
    list.add(fund);
  }

  final groups = [
    for (final id in order)
      (
        companyId: id,
        companyName: names[id] ?? _unknownCompany,
        funds: byCompany[id]!,
      ),
  ];

  groups.sort((a, b) {
    final aUnknown = a.companyName == _unknownCompany;
    final bUnknown = b.companyName == _unknownCompany;
    if (aUnknown != bUnknown) return aUnknown ? 1 : -1;
    return a.companyName.toLowerCase().compareTo(b.companyName.toLowerCase());
  });

  return groups;
}
