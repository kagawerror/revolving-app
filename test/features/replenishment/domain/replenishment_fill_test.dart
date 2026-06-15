import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_fill.dart';

void main() {
  ReplenishmentItem item(bool isPartial) => ReplenishmentItem(
        requestId: 'r',
        isPartial: isPartial,
        amount: Money.fromCentavos(100),
        remarks: isPartial ? 'note' : '',
      );

  group('computeFill', () {
    test('empty list is full (no partials present)', () {
      expect(computeFill(const []), ReplenishmentFill.full);
    });

    test('single full item is full', () {
      expect(computeFill([item(false)]), ReplenishmentFill.full);
    });

    test('single partial item is partial', () {
      expect(computeFill([item(true)]), ReplenishmentFill.partial);
    });

    test('all-full multi is full', () {
      expect(computeFill([item(false), item(false), item(false)]),
          ReplenishmentFill.full);
    });

    test('all-partial multi is partial', () {
      expect(computeFill([item(true), item(true)]), ReplenishmentFill.partial);
    });

    test('mixed full + partial is mixed', () {
      expect(computeFill([item(false), item(true)]), ReplenishmentFill.mixed);
    });
  });

  group('ReplenishmentFill.fromName', () {
    test('round-trips every .name', () {
      for (final f in ReplenishmentFill.values) {
        expect(ReplenishmentFill.fromName(f.name), f);
      }
    });

    test('null name returns null', () {
      expect(ReplenishmentFill.fromName(null), isNull);
    });

    test('garbage name returns null', () {
      expect(ReplenishmentFill.fromName('nonsense'), isNull);
    });
  });
}
