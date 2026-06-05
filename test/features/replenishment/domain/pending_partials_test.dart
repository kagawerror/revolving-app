import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/domain/pending_partials.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';

Replenishment _rep(String id, List<ReplenishmentItem> items) => Replenishment(
      id: id,
      companyId: 'c1',
      fundId: 'f1',
      status: ReplenishmentStatus.submitted,
      requestIds: items.map((i) => i.requestId).toList(),
      total:
          Money.fromCentavos(items.fold(0, (s, i) => s + i.amount.centavos)),
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

void main() {
  test('empty input yields an empty map', () {
    expect(partialAmountByRequest(const <Replenishment>[]), isEmpty);
  });

  test('sums multiple partial items across replenishments per requestId', () {
    final reps = [
      _rep('rep1', [_item('reqA', 1000000), _item('reqB', 500000)]),
      _rep('rep2', [_item('reqA', 1000000)]),
    ];

    final map = partialAmountByRequest(reps);

    expect(map['reqA']!.centavos, 2000000);
    expect(map['reqB']!.centavos, 500000);
    expect(map.containsKey('reqC'), isFalse);
  });

  test('excludes full (isPartial:false) items', () {
    final reps = [
      _rep('rep1', [
        _item('reqB', 750000, isPartial: false),
      ]),
    ];

    expect(partialAmountByRequest(reps), isEmpty);
  });

  test('mixed full + partial for the same requestId counts only the partial',
      () {
    final reps = [
      _rep('rep1', [
        _item('reqA', 300000, isPartial: true),
        _item('reqA', 1000000, isPartial: false),
        _item('reqC', 250000, isPartial: true),
      ]),
      _rep('rep2', [_item('reqC', 125000, isPartial: true)]),
    ];

    final map = partialAmountByRequest(reps);

    expect(map['reqA']!.centavos, 300000);
    expect(map['reqC']!.centavos, 375000);
  });
}
