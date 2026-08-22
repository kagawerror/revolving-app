import 'replenishment.dart';

/// How a replenishment report fills its line items, for at-a-glance display:
/// every item paid in full, every item partial, or a mix of both.
enum ReplenishmentFill {
  full,
  partial,
  mixed;

  /// Null-tolerant parse: matches by [name], else null (legacy/garbage values).
  static ReplenishmentFill? fromName(String? n) {
    if (n == null) return null;
    for (final f in values) {
      if (f.name == n) return f;
    }
    return null;
  }
}

/// Pure classification of a replenishment by its line items.
///
/// An empty list is treated as [ReplenishmentFill.full] (no partials present).
/// If every item is full -> full; if every item is partial -> partial;
/// otherwise -> mixed.
ReplenishmentFill computeFill(List<ReplenishmentItem> items) {
  if (items.isEmpty) return ReplenishmentFill.full;
  final anyPartial = items.any((i) => i.isPartial);
  final anyFull = items.any((i) => !i.isPartial);
  if (anyPartial && anyFull) return ReplenishmentFill.mixed;
  return anyPartial ? ReplenishmentFill.partial : ReplenishmentFill.full;
}
