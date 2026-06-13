import 'outbox_entry.dart';

/// Orders outbox entries for a drain pass so replays are FK-safe and deduped:
///
///  1. DEDUPE by [OutboxEntry.clientActionId] — keep the FIRST occurrence
///     (idempotency: the same action enqueued twice replays once).
///  2. FK ORDER per entity: a `createRequest` for an entityId must replay before
///     any `release`/`transition`/`approverDecision` on that same entityId,
///     otherwise the dependent write hits a missing parent.
///  3. Otherwise STABLE by [OutboxEntry.createdAtMillis] (ties keep input order).
///
/// Pure; does not mutate the input list.
List<OutboxEntry> orderForDrain(List<OutboxEntry> entries) {
  // 1. Dedupe by clientActionId, keeping first occurrence (stable).
  final seen = <String>{};
  final deduped = <OutboxEntry>[];
  for (final e in entries) {
    if (seen.add(e.clientActionId)) deduped.add(e);
  }

  // Group time = the earliest createdAtMillis among an entity's entries. Sorting
  // primarily by group time (then create-first within a group) keeps the
  // comparator transitive while guaranteeing a create replays before any
  // dependent write on the SAME entity, even if that create was enqueued later.
  final groupTime = <String, int>{};
  for (final e in deduped) {
    final cur = groupTime[e.entityId];
    if (cur == null || e.createdAtMillis < cur) {
      groupTime[e.entityId] = e.createdAtMillis;
    }
  }

  // Stable index map so equal sort keys preserve input order. Keyed by the
  // unique entry [id], NOT the Equatable entry itself: two value-equal-but-
  // distinct entries would collapse into one map key and lose their tiebreak
  // index. (Dedupe is by clientActionId; ids stay distinct across entries.)
  final inputIndex = <String, int>{
    for (var i = 0; i < deduped.length; i++) deduped[i].id: i,
  };

  int createRank(OutboxEntry e) => e.kind == OutboxKind.createRequest ? 0 : 1;

  final sorted = [...deduped];
  sorted.sort((a, b) {
    final byGroup = groupTime[a.entityId]!.compareTo(groupTime[b.entityId]!);
    if (byGroup != 0) return byGroup;
    // Same group time (same entity, or a coincidental tie): create first, then
    // per-entry time, then input order.
    if (a.entityId == b.entityId) {
      final byKind = createRank(a).compareTo(createRank(b));
      if (byKind != 0) return byKind;
    }
    final byTime = a.createdAtMillis.compareTo(b.createdAtMillis);
    if (byTime != 0) return byTime;
    return inputIndex[a.id]!.compareTo(inputIndex[b.id]!);
  });
  return sorted;
}
