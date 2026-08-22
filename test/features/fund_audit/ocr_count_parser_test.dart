import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/fund_audit/domain/denomination.dart';
import 'package:rev_app/features/fund_audit/domain/fund_audit_math.dart';
import 'package:rev_app/features/fund_audit/domain/ocr_count_parser.dart';
import 'package:rev_app/features/fund_audit/domain/ocr_text_service.dart';

List<RecognizedLine> _lines(List<String> texts) =>
    texts.map(RecognizedLine.new).toList();

void main() {
  group('parseDenominationCounts', () {
    test('full sheet maps every row', () {
      final lines = _lines([
        '1000 x 2 = 2000',
        '500 x 1 = 500',
        '200 x 3 = 600',
        '100 x 4 = 400',
        '50 x 2 = 100',
        '20 x 5 = 100',
        '10 x 6 = 60',
        '5 x 3 = 15',
        '1 x 9 = 9',
      ]);
      final map = parseDenominationCounts(lines);
      expect(map[Denomination.p1000], 2);
      expect(map[Denomination.p500], 1);
      expect(map[Denomination.p200], 3);
      expect(map[Denomination.p100], 4);
      expect(map[Denomination.p50], 2);
      expect(map[Denomination.p20], 5);
      expect(map[Denomination.p10], 6);
      expect(map[Denomination.p5], 3);
      expect(map[Denomination.p1], 9);
    });

    test('garbage returns empty map and never throws', () {
      final map = parseDenominationCounts(_lines([
        'hello world',
        'no numbers here',
        '!!! ??? ...',
        '',
      ]));
      expect(map, isEmpty);
    });

    test('rows that are not found are simply omitted', () {
      final map = parseDenominationCounts(_lines([
        '1000 x 2 = 2000',
        'this line is nonsense',
      ]));
      expect(map.length, 1);
      expect(map[Denomination.p1000], 2);
    });

    test('denomination present but no count is omitted', () {
      // A lone face value with no second number carries no count.
      final map = parseDenominationCounts(_lines(['1000']));
      expect(map, isEmpty);
    });

    test('zero count rows are omitted', () {
      final map = parseDenominationCounts(_lines(['100 x 0 = 0']));
      expect(map.containsKey(Denomination.p100), isFalse);
    });

    test('tolerant of comma punctuation in thousands', () {
      final map = parseDenominationCounts(_lines(['1,000 x 5 = 5,000']));
      expect(map[Denomination.p1000], 5);
    });

    test('does not confuse 1000 face value with 100', () {
      final map = parseDenominationCounts(_lines(['1000 x 1 = 1000']));
      expect(map.containsKey(Denomination.p100), isFalse);
      expect(map[Denomination.p1000], 1);
    });

    test('centavo coins matched by decimal text, not integer collision', () {
      final map = parseDenominationCounts(_lines([
        '0.25 x 4 = 1.00',
        '0.05 x 2 = 0.10',
        '0.01 x 3 = 0.03',
      ]));
      expect(map[Denomination.c25], 4);
      expect(map[Denomination.c05], 2);
      expect(map[Denomination.c01], 3);
      // The decimal-coin lines must NOT be read as ₱25 / ₱5 / ₱1 pesos.
      expect(map.containsKey(Denomination.c10), isFalse);
    });

    test('handles spaced / colon formatting tolerantly', () {
      final map = parseDenominationCounts(_lines([
        '500  :  3',
        '20    7',
      ]));
      expect(map[Denomination.p500], 3);
      expect(map[Denomination.p20], 7);
    });

    test('REAL sample sheet: decimal/comma denominations, subtotal ignored', () {
      // The exact attached fixture: every denomination written with two decimal
      // places, thousands commas, in "<denom> x <count> = <subtotal>" shape.
      // Blank-count rows ("0.01 x   = -") must be omitted, never crash.
      final lines = _lines([
        '0.01 x   = -',
        '0.05 x   = -',
        '0.10 x   = -',
        '0.25 x   = -',
        '1.00 x 8 = 8.00',
        '5.00 x 1 = 5.00',
        '10.00 x 1 = 10.00',
        '20.00 x   = -',
        '50.00 x 2 = 100.00',
        '100.00 x 2 = 200.00',
        '200.00 x   = -',
        '500.00 x   = -',
        '1,000.00 x 2 = 2,000.00',
      ]);
      final map = parseDenominationCounts(lines);
      expect(map, {
        Denomination.p1: 8,
        Denomination.p5: 1,
        Denomination.p10: 1,
        Denomination.p50: 2,
        Denomination.p100: 2,
        Denomination.p1000: 2,
      });
      // The decimal denominations must NOT be mis-read as centavo coins.
      expect(map.containsKey(Denomination.c01), isFalse);
      // And the total of the parsed sheet is ₱2,323.00.
      expect(sumDenominations(map).centavos, 232300);
    });

    test('decimal coin with a real count reads as the centavo coin', () {
      final map = parseDenominationCounts(_lines(['0.25 x 4 = 1.00']));
      expect(map, {Denomination.c25: 4});
    });

    test('ten ₱10 bills: count 10 not confused with the denomination', () {
      final map = parseDenominationCounts(_lines(['10.00 x 10 = 100.00']));
      expect(map, {Denomination.p10: 10});
    });

    test('decimal 1000 face value is not mis-read as 100', () {
      final map = parseDenominationCounts(_lines(['1,000.00 x 1 = 1,000.00']));
      expect(map.containsKey(Denomination.p100), isFalse);
      expect(map[Denomination.p1000], 1);
    });

    test('decimal 10.00 face value is not mis-read as 100', () {
      final map = parseDenominationCounts(_lines(['10.00 x 1 = 10.00']));
      expect(map.containsKey(Denomination.p100), isFalse);
      expect(map[Denomination.p10], 1);
    });

    test('blank-count decimal row is omitted, never throws', () {
      final map = parseDenominationCounts(_lines(['0.01 x   = -']));
      expect(map, isEmpty);
    });

    test('garbage with decimals still returns empty and never throws', () {
      final map = parseDenominationCounts(_lines([
        '3.14 pie',
        '99.99 x 1 = 99.99', // 9999c is not a face value
        '????',
      ]));
      expect(map, isEmpty);
    });
  });
}
