import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/reports/domain/report_period.dart';

void main() {
  group('periodWindow', () {
    test('day is midnight to next midnight', () {
      final w = periodWindow(
        PeriodGranularity.day,
        DateTime(2026, 6, 13, 15, 42),
      );
      expect(w.start, DateTime(2026, 6, 13));
      expect(w.endExclusive, DateTime(2026, 6, 14));
    });

    test('week starts Monday and ends next Monday (ISO Monday start)', () {
      // 2026-06-13 is a Saturday; the Monday of that week is 2026-06-08.
      final w = periodWindow(PeriodGranularity.week, DateTime(2026, 6, 13));
      expect(w.start, DateTime(2026, 6, 8)); // Monday
      expect(w.start.weekday, DateTime.monday);
      expect(w.endExclusive, DateTime(2026, 6, 15)); // next Monday
    });

    test('week containing a Monday anchors to that Monday', () {
      final w = periodWindow(PeriodGranularity.week, DateTime(2026, 6, 8));
      expect(w.start, DateTime(2026, 6, 8));
    });

    test('week containing a Sunday anchors back to its Monday', () {
      // 2026-06-14 is a Sunday; its Monday is 2026-06-08.
      final w = periodWindow(PeriodGranularity.week, DateTime(2026, 6, 14));
      expect(w.start, DateTime(2026, 6, 8));
      expect(w.endExclusive, DateTime(2026, 6, 15));
    });

    test('month is 1st to 1st of next month (year rollover)', () {
      final w = periodWindow(PeriodGranularity.month, DateTime(2026, 12, 20));
      expect(w.start, DateTime(2026, 12, 1));
      expect(w.endExclusive, DateTime(2027, 1, 1));
    });

    test('month handles February without Duration math', () {
      final w = periodWindow(PeriodGranularity.month, DateTime(2024, 2, 15));
      expect(w.start, DateTime(2024, 2, 1));
      expect(w.endExclusive, DateTime(2024, 3, 1));
    });

    test('year is Jan 1 to Jan 1 next year', () {
      final w = periodWindow(PeriodGranularity.year, DateTime(2026, 8, 3));
      expect(w.start, DateTime(2026, 1, 1));
      expect(w.endExclusive, DateTime(2027, 1, 1));
    });
  });

  group('DateRange.contains (half-open)', () {
    test('includes start, excludes endExclusive', () {
      final w = DateRange(
        start: DateTime(2026, 6, 13),
        endExclusive: DateTime(2026, 6, 14),
      );
      expect(w.contains(DateTime(2026, 6, 13)), isTrue);
      expect(w.contains(DateTime(2026, 6, 13, 23, 59, 59)), isTrue);
      expect(w.contains(DateTime(2026, 6, 14)), isFalse);
      expect(w.contains(DateTime(2026, 6, 12, 23, 59, 59)), isFalse);
    });
  });

  group('previousPeriod / nextPeriod', () {
    test('day steps by one calendar day', () {
      final p = ReportPeriod(
        granularity: PeriodGranularity.day,
        anchor: DateTime(2026, 6, 1),
      );
      expect(previousPeriod(p).anchor, DateTime(2026, 5, 31));
      expect(nextPeriod(p).anchor, DateTime(2026, 6, 2));
    });

    test('week steps by seven days', () {
      final p = ReportPeriod(
        granularity: PeriodGranularity.week,
        anchor: DateTime(2026, 6, 8),
      );
      expect(previousPeriod(p).anchor, DateTime(2026, 6, 1));
      expect(nextPeriod(p).anchor, DateTime(2026, 6, 15));
    });

    test('month rolls over Jan to Dec of previous year', () {
      final p = ReportPeriod(
        granularity: PeriodGranularity.month,
        anchor: DateTime(2026, 1, 31),
      );
      // Anchored to the 1st before stepping, so no Feb-31 overflow.
      expect(previousPeriod(p).anchor, DateTime(2025, 12, 1));
      expect(nextPeriod(p).anchor, DateTime(2026, 2, 1));
    });

    test('month from a 31st does not skip a short month', () {
      final p = ReportPeriod(
        granularity: PeriodGranularity.month,
        anchor: DateTime(2026, 3, 31),
      );
      // Previous should be February, not "March 3" from a Feb-31 overflow.
      final prev = previousPeriod(p);
      expect(prev.anchor.month, 2);
      expect(periodWindow(prev.granularity, prev.anchor).start,
          DateTime(2026, 2, 1));
    });

    test('year steps by one year', () {
      final p = ReportPeriod(
        granularity: PeriodGranularity.year,
        anchor: DateTime(2026, 6, 13),
      );
      expect(previousPeriod(p).anchor, DateTime(2025, 1, 1));
      expect(nextPeriod(p).anchor, DateTime(2027, 1, 1));
    });
  });

  group('periodLabel', () {
    test('day', () {
      expect(
        periodLabel(ReportPeriod(
          granularity: PeriodGranularity.day,
          anchor: DateTime(2026, 6, 13),
        )),
        'Jun 13, 2026',
      );
    });

    test('week within one month', () {
      expect(
        periodLabel(ReportPeriod(
          granularity: PeriodGranularity.week,
          anchor: DateTime(2026, 6, 13),
        )),
        'Jun 8–14, 2026',
      );
    });

    test('month', () {
      expect(
        periodLabel(ReportPeriod(
          granularity: PeriodGranularity.month,
          anchor: DateTime(2026, 6, 13),
        )),
        'June 2026',
      );
    });

    test('year', () {
      expect(
        periodLabel(ReportPeriod(
          granularity: PeriodGranularity.year,
          anchor: DateTime(2026, 6, 13),
        )),
        '2026',
      );
    });
  });

  group('isCurrentPeriod', () {
    test('true when now is inside the window', () {
      final p = ReportPeriod(
        granularity: PeriodGranularity.month,
        anchor: DateTime(2026, 6, 1),
      );
      expect(isCurrentPeriod(p, DateTime(2026, 6, 30, 23, 59)), isTrue);
    });

    test('false when now is outside the window', () {
      final p = ReportPeriod(
        granularity: PeriodGranularity.month,
        anchor: DateTime(2026, 6, 1),
      );
      expect(isCurrentPeriod(p, DateTime(2026, 7, 1)), isFalse);
    });
  });
}
