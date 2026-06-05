import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/requests/domain/aging.dart';

void main() {
  group('agingDays', () {
    test('same calendar day is 0', () {
      expect(agingDays(DateTime(2026, 6, 5), DateTime(2026, 6, 5)), 0);
    });

    test('30 days', () {
      expect(agingDays(DateTime(2026, 5, 6), DateTime(2026, 6, 5)), 30);
    });

    test('31 days', () {
      expect(agingDays(DateTime(2026, 5, 5), DateTime(2026, 6, 5)), 31);
    });

    test('60 days', () {
      expect(agingDays(DateTime(2026, 4, 6), DateTime(2026, 6, 5)), 60);
    });

    test('61 days', () {
      expect(agingDays(DateTime(2026, 4, 5), DateTime(2026, 6, 5)), 61);
    });

    test('time-of-day is ignored: 23:59 vs next-day 00:01 is 1 day', () {
      expect(
        agingDays(DateTime(2026, 6, 4, 23, 59), DateTime(2026, 6, 5, 0, 1)),
        1,
      );
    });

    test('future createdAt clamps to 0', () {
      expect(agingDays(DateTime(2026, 6, 10), DateTime(2026, 6, 5)), 0);
    });
  });

  group('bucketFor', () {
    test('0 is green', () => expect(bucketFor(0), AgingBucket.green));
    test('30 is green', () => expect(bucketFor(30), AgingBucket.green));
    test('31 is amber', () => expect(bucketFor(31), AgingBucket.amber));
    test('60 is amber', () => expect(bucketFor(60), AgingBucket.amber));
    test('61 is red', () => expect(bucketFor(61), AgingBucket.red));
  });
}
