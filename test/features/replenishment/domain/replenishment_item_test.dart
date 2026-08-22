import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';

void main() {
  test('ReplenishmentItem round-trips through map', () {
    const item = ReplenishmentItem(
      requestId: 'r1', isPartial: true,
      amount: Money.zero, remarks: 'partial pay',
    );
    final back = ReplenishmentItem.fromMap(item.copyWithAmount(150000).toMap());
    expect(back.requestId, 'r1');
    expect(back.isPartial, isTrue);
    expect(back.amount.centavos, 150000);
    expect(back.remarks, 'partial pay');
  });

  test('Replenishment.fromMap parses items; legacy doc yields empty items', () {
    final withItems = Replenishment.fromMap('a', {
      'companyId': 'c1', 'fundId': 'f1', 'status': 'draft',
      'requestIds': ['r1'], 'totalCentavos': 150000, 'reportNotes': '',
      'createdByUid': 'inc',
      'items': [
        {'requestId': 'r1', 'isPartial': true, 'amountCentavos': 150000, 'remarks': 'x'}
      ],
    });
    expect(withItems.items.length, 1);
    expect(withItems.items.single.amount.centavos, 150000);

    final legacy = Replenishment.fromMap('b', {
      'companyId': 'c1', 'fundId': 'f1', 'status': 'approved',
      'requestIds': ['r1', 'r2'], 'totalCentavos': 800000, 'reportNotes': '',
      'createdByUid': 'inc',
    });
    expect(legacy.items, isEmpty);
    expect(legacy.requestIds, ['r1', 'r2']);
    expect(legacy.total.centavos, 800000);
  });
}
