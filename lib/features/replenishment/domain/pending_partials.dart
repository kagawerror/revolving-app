import '../../../core/money/money.dart';
import 'replenishment.dart';

/// Sums submitted-but-not-yet-approved PARTIAL replenishment item amounts per
/// requestId (full items excluded). Feeds the request breakdown's pending
/// "for approval" line. Pure — no I/O.
Map<String, Money> partialAmountByRequest(
    Iterable<Replenishment> replenishments) {
  final acc = <String, int>{};
  for (final rep in replenishments) {
    for (final item in rep.items) {
      if (!item.isPartial) continue;
      acc.update(item.requestId, (v) => v + item.amount.centavos,
          ifAbsent: () => item.amount.centavos);
    }
  }
  return acc.map((k, v) => MapEntry(k, Money.fromCentavos(v)));
}
