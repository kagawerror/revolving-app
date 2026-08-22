import 'package:flutter_test/flutter_test.dart';

import 'package:rev_app/features/fund_audit/domain/denomination.dart';
import 'package:rev_app/features/fund_audit/domain/fund_audit_math.dart';
import 'package:rev_app/features/fund_audit/domain/ocr_count_parser.dart';
import 'package:rev_app/features/fund_audit/domain/ocr_row_reconstructor.dart';
import 'package:rev_app/features/fund_audit/domain/ocr_text_service.dart';

/// A boxed fragment whose box is centered on [centerY] with the sheet's ~36px
/// row height (centerY±18).
RecognizedLine _frag(String text, double left, double right, double centerY) =>
    RecognizedLine(text, box: TextBox(left, centerY - 18, right, centerY + 18));

void main() {
  group('reconstructRows', () {
    test(
        'column-segmented sheet: reconstructs visual rows that parse into '
        'the right denomination counts (₱2,323.00)', () {
      // Two columns. Face-value column at left≈20, count column at left≈200.
      // Row N centerY ≈ 30 + N*50. Each box = (left, cY-18, right, cY+18).
      const faceValues = [
        '0.01',
        '0.05',
        '0.10',
        '0.20',
        '1.00',
        '5.00',
        '10.00',
        '20.00',
        '50.00',
        '100.00',
        '200.00',
        '500.00',
        '1000.00',
      ];
      // Counts aligned to the SAME y as their face rows. Only some rows have a
      // count fragment (others are blank on the sheet).
      const countByFace = <String, String>{
        '1.00': '8',
        '5.00': '1',
        '10.00': '1',
        '50.00': '2',
        '100.00': '2',
        '1000.00': '2',
      };

      final frags = <RecognizedLine>[];
      for (var n = 0; n < faceValues.length; n++) {
        final cY = 30.0 + n * 50.0;
        // ML Kit emits columns block-wise, so all face fragments come first…
        frags.add(_frag(faceValues[n], 20, 90, cY));
      }
      for (var n = 0; n < faceValues.length; n++) {
        final cY = 30.0 + n * 50.0;
        final c = countByFace[faceValues[n]];
        if (c != null) {
          // …then all count fragments, column-segmented after the faces.
          frags.add(_frag(c, 200, 240, cY));
        }
      }

      final rows = reconstructRows(frags);
      final counts = parseDenominationCounts(rows);

      expect(counts, {
        Denomination.p1: 8,
        Denomination.p5: 1,
        Denomination.p10: 1,
        Denomination.p50: 2,
        Denomination.p100: 2,
        Denomination.p1000: 2,
      });
      // ₱2,323.00 = 232300 centavos, computed via the domain helper.
      expect(sumDenominations(counts).centavos, 232300);
    });

    test('row-wise no-regression: whole-row boxed fragments stay parseable', () {
      final frags = <RecognizedLine>[
        _frag('1000.00 x 2 = 2000.00', 20, 300, 30),
        _frag('100.00 x 5 = 500.00', 20, 300, 80),
        _frag('50.00 x 3 = 150.00', 20, 300, 130),
      ];
      final rows = reconstructRows(frags);
      final counts = parseDenominationCounts(rows);
      expect(counts, {
        Denomination.p1000: 2,
        Denomination.p100: 5,
        Denomination.p50: 3,
      });
    });

    test('zero-geometry fallback: all null boxes returned unchanged + parse', () {
      const frags = <RecognizedLine>[
        RecognizedLine('1000 x 2 = 2000'),
        RecognizedLine('100 x 5 = 500'),
      ];
      final rows = reconstructRows(frags);
      expect(rows, frags); // unchanged, row-wise preserved
      expect(parseDenominationCounts(rows), {
        Denomination.p1000: 2,
        Denomination.p100: 5,
      });
    });

    test('zero-geometry fallback: all zero-height boxes returned unchanged', () {
      final frags = <RecognizedLine>[
        RecognizedLine('1000 x 2 = 2000', box: const TextBox(0, 10, 100, 10)),
        RecognizedLine('100 x 5 = 500', box: const TextBox(0, 60, 100, 60)),
      ];
      final rows = reconstructRows(frags);
      expect(rows, frags);
      expect(parseDenominationCounts(rows), {
        Denomination.p1000: 2,
        Denomination.p100: 5,
      });
    });

    test('empty input returns empty', () {
      expect(reconstructRows(const []), isEmpty);
    });

    test('nothing matches: boxed garbage reconstructs but parses to {}', () {
      final frags = <RecognizedLine>[
        _frag('hello', 20, 90, 30),
        _frag('world', 200, 260, 30),
        _frag('foo', 20, 90, 80),
      ];
      Map<Denomination, int>? counts;
      expect(() {
        final rows = reconstructRows(frags);
        counts = parseDenominationCounts(rows);
      }, returnsNormally);
      expect(counts, <Denomination, int>{});
    });

    test('skew: same-row fragments within tol cluster; adjacent rows do not', () {
      // Two fragments on the "same" row but skewed by 8px (< tol). Heights 36 →
      // tol = max(36*0.6, 1) = 21.6, so 8px skew merges.
      final frags = <RecognizedLine>[
        _frag('1000.00', 20, 90, 30),
        _frag('2', 200, 240, 38), // +8px skew, same visual row
        // Next row, 50px down — must NOT merge with the first.
        _frag('100.00', 20, 90, 80),
        _frag('5', 200, 240, 80),
      ];
      final rows = reconstructRows(frags);
      final counts = parseDenominationCounts(rows);
      expect(counts, {
        Denomination.p1000: 2,
        Denomination.p100: 5,
      });
      // Two visual rows reconstructed (skewed pair merged, not the next row).
      expect(rows, hasLength(2));
    });

    test('mixed null + boxed: boxed cluster, null appended, no text dropped', () {
      final frags = <RecognizedLine>[
        _frag('1000.00', 20, 90, 30),
        _frag('2', 200, 240, 30),
        const RecognizedLine('100 x 5 = 500'), // null box — appended as own row
      ];
      final rows = reconstructRows(frags);
      // No text dropped: every fragment's text survives somewhere.
      final joined = rows.map((r) => r.text).join(' | ');
      expect(joined.contains('1000.00'), isTrue);
      expect(joined.contains('100 x 5 = 500'), isTrue);
      final counts = parseDenominationCounts(rows);
      expect(counts, {
        Denomination.p1000: 2,
        Denomination.p100: 5,
      });
    });
  });
}
