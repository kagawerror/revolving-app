import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/sync/domain/outbox_entry.dart';
import 'package:rev_app/features/sync/domain/outbox_ordering.dart';

OutboxEntry _e({
  required String id,
  required OutboxKind kind,
  required String entityId,
  required int t,
  String? cid,
}) =>
    OutboxEntry(
      id: id,
      kind: kind,
      companyId: 'c1',
      entityId: entityId,
      clientActionId: cid ?? id,
      createdAtMillis: t,
    );

void main() {
  group('orderForDrain', () {
    test('createRequest precedes a release on the same entity, even if the '
        'release was enqueued earlier', () {
      final release = _e(id: '1', kind: OutboxKind.release, entityId: 'X', t: 5);
      final create =
          _e(id: '2', kind: OutboxKind.createRequest, entityId: 'X', t: 10);
      final ordered = orderForDrain([release, create]);
      expect(ordered.map((e) => e.id), ['2', '1']);
    });

    test('dedupes by clientActionId, keeping the first occurrence', () {
      final a = _e(id: '1', kind: OutboxKind.release, entityId: 'X', t: 1, cid: 'dup');
      final b = _e(id: '2', kind: OutboxKind.release, entityId: 'X', t: 2, cid: 'dup');
      final ordered = orderForDrain([a, b]);
      expect(ordered.length, 1);
      expect(ordered.single.id, '1');
    });

    test('orders unrelated entities by createdAtMillis', () {
      final y = _e(id: 'y', kind: OutboxKind.transition, entityId: 'Y', t: 30);
      final x = _e(id: 'x', kind: OutboxKind.transition, entityId: 'X', t: 10);
      final z = _e(id: 'z', kind: OutboxKind.transition, entityId: 'Z', t: 20);
      final ordered = orderForDrain([y, x, z]);
      expect(ordered.map((e) => e.id), ['x', 'z', 'y']);
    });

    test('stable on equal createdAtMillis (preserves input order)', () {
      final a = _e(id: 'a', kind: OutboxKind.transition, entityId: 'A', t: 5);
      final b = _e(id: 'b', kind: OutboxKind.transition, entityId: 'B', t: 5);
      final ordered = orderForDrain([a, b]);
      expect(ordered.map((e) => e.id), ['a', 'b']);
      final ordered2 = orderForDrain([b, a]);
      expect(ordered2.map((e) => e.id), ['b', 'a']);
    });

    test('FK order keeps create-then-release grouped ahead of a later entity', () {
      // Entity X: create@10, release@5 (must replay create first, group@5).
      // Entity Y: transition@7 → between X group time (5) and X release time.
      final create =
          _e(id: 'cx', kind: OutboxKind.createRequest, entityId: 'X', t: 10);
      final release =
          _e(id: 'rx', kind: OutboxKind.release, entityId: 'X', t: 5);
      final yMove =
          _e(id: 'ty', kind: OutboxKind.transition, entityId: 'Y', t: 7);
      final ordered = orderForDrain([yMove, release, create]);
      // X group time is 5 (earliest in group) < Y's 7, and within X create wins.
      expect(ordered.map((e) => e.id), ['cx', 'rx', 'ty']);
    });

    test('two value-equal-but-distinct entries keep stable input order '
        '(tiebreak index keyed by id, not the Equatable entry)', () {
      // Identical in every Equatable-relevant field EXCEPT id and clientActionId
      // (so they survive dedupe), same entity + same time → the only tiebreak is
      // input order. Keying the index map by the entry itself would collapse
      // these and corrupt the order; keying by id keeps them distinct.
      final first = OutboxEntry(
        id: 'first',
        kind: OutboxKind.transition,
        companyId: 'c1',
        entityId: 'X',
        clientActionId: 'a1',
        createdAtMillis: 100,
      );
      final second = OutboxEntry(
        id: 'second',
        kind: OutboxKind.transition,
        companyId: 'c1',
        entityId: 'X',
        clientActionId: 'a2',
        createdAtMillis: 100,
      );
      expect(orderForDrain([first, second]).map((e) => e.id), ['first', 'second']);
      expect(orderForDrain([second, first]).map((e) => e.id), ['second', 'first']);
    });

    test('empty input → empty output', () {
      expect(orderForDrain(const []), isEmpty);
    });
  });
}
