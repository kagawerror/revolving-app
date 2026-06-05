import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';
import 'package:rev_app/features/replenishment/presentation/replenishment_providers.dart';

Replenishment _rep(String id, List<ReplenishmentItem> items) => Replenishment(
      id: id,
      companyId: 'c1',
      fundId: 'f1',
      status: ReplenishmentStatus.submitted,
      requestIds: items.map((i) => i.requestId).toList(),
      total: Money.fromCentavos(
          items.fold(0, (s, i) => s + i.amount.centavos)),
      reportNotes: '',
      createdByUid: 'inc',
      items: items,
    );

ReplenishmentItem _item(String requestId, int centavos,
        {bool isPartial = true}) =>
    ReplenishmentItem(
      requestId: requestId,
      isPartial: isPartial,
      amount: Money.fromCentavos(centavos),
    );

ProviderContainer _containerWith(List<Replenishment> reps) {
  final c = ProviderContainer(overrides: [
    pendingReplenishmentsProvider.overrideWith((ref) => Stream.value(reps)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('empty when there are no submitted replenishments', () async {
    final c = _containerWith(const []);
    // Resolve the underlying stream first.
    await c.read(pendingReplenishmentsProvider.future);
    final map = c.read(pendingPartialByRequestProvider);
    expect(map, isEmpty);
  });

  test('sums items across multiple submitted replenishments per requestId',
      () async {
    final reps = [
      _rep('rep1', [_item('reqA', 1000000), _item('reqB', 500000)]),
      _rep('rep2', [_item('reqA', 1000000)]),
    ];
    final c = _containerWith(reps);
    await c.read(pendingReplenishmentsProvider.future);
    final map = c.read(pendingPartialByRequestProvider);

    expect(map['reqA']!.centavos, 2000000);
    expect(map['reqB']!.centavos, 500000);
    expect(map.containsKey('reqC'), isFalse);
  });

  test('excludes full items and sums only partial items per requestId',
      () async {
    final reps = [
      _rep('rep1', [
        // reqA: one partial + one full → only the partial counts.
        _item('reqA', 300000, isPartial: true),
        _item('reqA', 1000000, isPartial: false),
        // reqB: full only → excluded entirely.
        _item('reqB', 750000, isPartial: false),
        // reqC: partial → included.
        _item('reqC', 250000, isPartial: true),
      ]),
      // Another partial for reqC in a second submitted replenishment.
      _rep('rep2', [_item('reqC', 125000, isPartial: true)]),
    ];
    final c = _containerWith(reps);
    await c.read(pendingReplenishmentsProvider.future);
    final map = c.read(pendingPartialByRequestProvider);

    expect(map['reqA']!.centavos, 300000);
    expect(map.containsKey('reqB'), isFalse);
    expect(map['reqC']!.centavos, 375000);
  });
}
