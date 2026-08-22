import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

/// Granularity of a report window. Re-exported by `report_providers.dart` so the
/// presentation layer (segmented control) imports it from one place.
enum PeriodGranularity { day, week, month, year }

/// A half-open date window `[start, endExclusive)`. All boundaries are local,
/// midnight-aligned. Half-open so adjacent windows tile with no overlap and a
/// timestamp lands in exactly one window.
class DateRange extends Equatable {
  const DateRange({required this.start, required this.endExclusive});

  final DateTime start;
  final DateTime endExclusive;

  /// True when [t] falls within `[start, endExclusive)`.
  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(endExclusive);

  @override
  List<Object?> get props => [start, endExclusive];
}

/// The active report window: a [granularity] plus an [anchor] date that lands
/// somewhere inside the window. The concrete start/end come from [periodWindow].
class ReportPeriod extends Equatable {
  const ReportPeriod({required this.granularity, required this.anchor});

  final PeriodGranularity granularity;
  final DateTime anchor;

  ReportPeriod copyWith({PeriodGranularity? granularity, DateTime? anchor}) =>
      ReportPeriod(
        granularity: granularity ?? this.granularity,
        anchor: anchor ?? this.anchor,
      );

  @override
  List<Object?> get props => [granularity, anchor];
}

/// Resolves the concrete `[start, endExclusive)` window for [g] around [anchor].
///
/// Calendar math only — never `Duration(days: 30)` — so month/year boundaries
/// stay exact across variable-length months and leap years:
///   * day   → midnight of [anchor] → next midnight.
///   * week  → Monday 00:00 of [anchor]'s ISO week → next Monday (Mon-start).
///   * month → 1st 00:00 → 1st of next month.
///   * year  → Jan 1 00:00 → Jan 1 of next year.
DateRange periodWindow(PeriodGranularity g, DateTime anchor) {
  switch (g) {
    case PeriodGranularity.day:
      final start = DateTime(anchor.year, anchor.month, anchor.day);
      return DateRange(
        start: start,
        endExclusive: DateTime(anchor.year, anchor.month, anchor.day + 1),
      );
    case PeriodGranularity.week:
      // DateTime.weekday is 1 (Mon) .. 7 (Sun); back up to Monday.
      final midnight = DateTime(anchor.year, anchor.month, anchor.day);
      final start = DateTime(
        midnight.year,
        midnight.month,
        midnight.day - (midnight.weekday - DateTime.monday),
      );
      return DateRange(
        start: start,
        endExclusive: DateTime(start.year, start.month, start.day + 7),
      );
    case PeriodGranularity.month:
      final start = DateTime(anchor.year, anchor.month, 1);
      return DateRange(
        start: start,
        endExclusive: DateTime(anchor.year, anchor.month + 1, 1),
      );
    case PeriodGranularity.year:
      return DateRange(
        start: DateTime(anchor.year, 1, 1),
        endExclusive: DateTime(anchor.year + 1, 1, 1),
      );
  }
}

/// The period one unit before [p]. Anchor math uses `DateTime(y, m-1, 1)` /
/// `DateTime(y-1, ...)` so month/year rollover is correct (Jan → Dec prev year)
/// and never produces an invalid date (anchor normalized to the 1st/Monday
/// before stepping where day-of-month would otherwise overflow).
ReportPeriod previousPeriod(ReportPeriod p) => _shift(p, -1);

/// The period one unit after [p]. See [previousPeriod].
ReportPeriod nextPeriod(ReportPeriod p) => _shift(p, 1);

ReportPeriod _shift(ReportPeriod p, int sign) {
  final a = p.anchor;
  switch (p.granularity) {
    case PeriodGranularity.day:
      return p.copyWith(anchor: DateTime(a.year, a.month, a.day + sign));
    case PeriodGranularity.week:
      return p.copyWith(anchor: DateTime(a.year, a.month, a.day + 7 * sign));
    case PeriodGranularity.month:
      // Anchor on the 1st so a 31st anchor can't skip a short month.
      return p.copyWith(anchor: DateTime(a.year, a.month + sign, 1));
    case PeriodGranularity.year:
      return p.copyWith(anchor: DateTime(a.year + sign, 1, 1));
  }
}

/// Human label for the active period:
///   * day   → "Jun 13, 2026"
///   * week  → "Jun 9–15, 2026" (Mon–Sun; spans months/years when needed)
///   * month → "June 2026"
///   * year  → "2026"
String periodLabel(ReportPeriod p) {
  switch (p.granularity) {
    case PeriodGranularity.day:
      return DateFormat('MMM d, yyyy').format(p.anchor);
    case PeriodGranularity.week:
      final w = periodWindow(PeriodGranularity.week, p.anchor);
      final start = w.start;
      final end = DateTime(w.start.year, w.start.month, w.start.day + 6);
      if (start.year != end.year) {
        // Spans a year boundary: spell both years.
        return '${DateFormat('MMM d, yyyy').format(start)} – '
            '${DateFormat('MMM d, yyyy').format(end)}';
      }
      if (start.month != end.month) {
        // Spans a month boundary within one year: "Jun 30 – Jul 6, 2026".
        return '${DateFormat('MMM d').format(start)} – '
            '${DateFormat('MMM d, yyyy').format(end)}';
      }
      // Same month: "Jun 9–15, 2026".
      return '${DateFormat('MMM d').format(start)}–'
          '${DateFormat('d, yyyy').format(end)}';
    case PeriodGranularity.month:
      return DateFormat('MMMM yyyy').format(p.anchor);
    case PeriodGranularity.year:
      return DateFormat('yyyy').format(p.anchor);
  }
}

/// True when [p]'s window contains [now] — i.e. the period is the live one and
/// "next" should be disabled (no future data exists).
bool isCurrentPeriod(ReportPeriod p, DateTime now) =>
    periodWindow(p.granularity, p.anchor).contains(now);
