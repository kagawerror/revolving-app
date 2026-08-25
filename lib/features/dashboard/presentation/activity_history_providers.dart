import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../reports/domain/report_period.dart';
import '../../requests/domain/fund_request.dart';
import '../../requests/domain/request_repository.dart';
import '../../requests/presentation/request_providers.dart';
import 'dashboard_providers.dart';

/// Injectable "now" for the Activity-history section, so the default month/year
/// and the year dropdown's options are deterministic under test. Production
/// resolves to the real clock.
final activityHistoryClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// How many years the Year dropdown offers, counting back from (and including)
/// the current year.
const int activityHistoryYearSpan = 5;

/// The selectable years, newest first. Stops at the current year — a future
/// year could only ever render an empty archive.
final activityHistoryYearsProvider = Provider<List<int>>((ref) {
  final year = ref.watch(activityHistoryClockProvider)().year;
  return [for (var i = 0; i < activityHistoryYearSpan; i++) year - i];
});

/// The months selectable for the currently-picked year. Mirrors how the reports
/// screen refuses to step past [isCurrentPeriod]: in the CURRENT year the list
/// stops at the current month, because later months have not happened yet and
/// would just show a confusing "No activity in this period".
List<int> selectableMonths(int year, DateTime now) => [
      for (var m = 1; m <= (year == now.year ? now.month : 12); m++) m,
    ];

final activityHistoryMonthsProvider = Provider<List<int>>((ref) {
  final now = ref.watch(activityHistoryClockProvider)();
  return selectableMonths(ref.watch(activityHistoryFilterProvider).year, now);
});

/// Clamps a month/year onto the last window that can hold data, so no code path
/// (dropdown, clamp-on-year-change, or a future default) can select the future.
ActivityHistoryFilter clampToPast(ActivityHistoryFilter f, DateTime now) {
  final current = periodWindow(PeriodGranularity.month, now);
  if (!f.window.start.isAfter(current.start)) return f;
  return ActivityHistoryFilter(month: now.month, year: now.year);
}

/// The month/year the Activity-history section is browsing. A calendar month is
/// the only granularity offered, so the concrete window comes straight from the
/// shared [periodWindow] math rather than a second implementation.
class ActivityHistoryFilter extends Equatable {
  const ActivityHistoryFilter({required this.month, required this.year});

  /// The month/year [now] falls in — the section's default on first render.
  factory ActivityHistoryFilter.of(DateTime now) =>
      ActivityHistoryFilter(month: now.month, year: now.year);

  /// 1 (January) .. 12 (December).
  final int month;
  final int year;

  /// The half-open `[1st 00:00, 1st of next month 00:00)` window to query.
  DateRange get window =>
      periodWindow(PeriodGranularity.month, DateTime(year, month, 1));

  ActivityHistoryFilter copyWith({int? month, int? year}) =>
      ActivityHistoryFilter(month: month ?? this.month, year: year ?? this.year);

  @override
  List<Object?> get props => [month, year];
}

/// Holds the picked month/year.
///
/// Deliberately NOT autoDispose. The precedent for long-lived filter/session
/// state is `reportPeriodProvider` (the reports screen's period picker),
/// `dashboardCompanyIdProvider`, and `currentUserProvider` — all plain
/// providers. The autoDispose siblings on this dashboard are all *streams*,
/// where disposal closes a live Firestore listener; there is nothing to close
/// here. Concretely: the dashboard's outer `ListView` destroys off-screen
/// children, so an autoDispose filter would silently snap back to the current
/// month the moment the user scrolled up and back down.
class ActivityHistoryFilterNotifier extends Notifier<ActivityHistoryFilter> {
  @override
  ActivityHistoryFilter build() =>
      ActivityHistoryFilter.of(ref.read(activityHistoryClockProvider)());

  void setMonth(int month) => _set(state.copyWith(month: month));

  /// Changing the year can strand the month in the future (e.g. December 2025
  /// → 2026 while it is still June), so the result is clamped.
  void setYear(int year) => _set(state.copyWith(year: year));

  void _set(ActivityHistoryFilter next) =>
      state = clampToPast(next, ref.read(activityHistoryClockProvider)());
}

final activityHistoryFilterProvider =
    NotifierProvider<ActivityHistoryFilterNotifier, ActivityHistoryFilter>(
  ActivityHistoryFilterNotifier.new,
);

/// One rendered page of the Activity-history archive.
class ActivityHistoryState extends Equatable {
  const ActivityHistoryState({
    this.items = const [],
    this.loading = false,
    this.failure,
    this.cursors = const [],
    this.hasMore = false,
  });

  /// The rows of the CURRENT page only.
  final List<FundRequest> items;
  final bool loading;

  /// Non-null when the last fetch failed; [items] is then empty.
  final Failure? failure;

  /// The `before` cursor used for each page beyond the first — one entry per
  /// page already walked past, so "Previous" is just a pop. Empty on page 1.
  final List<PeriodCursor> cursors;

  /// A further page definitely exists — proven, not guessed: the fetch asks for
  /// one row more than it shows, and that extra row is the proof.
  final bool hasMore;

  /// 1-based, for the "Page N" label.
  int get pageNumber => cursors.length + 1;

  bool get canGoPrevious => cursors.isNotEmpty;

  bool get canGoNext => hasMore;

  /// True once the archive spans more than one page — the only case where the
  /// prev/next controls are worth showing at all.
  bool get isPaginated => cursors.isNotEmpty || hasMore;

  @override
  List<Object?> get props => [items, loading, failure, cursors, hasMore];
}

/// Drives the dashboard's Activity-history archive: a month/year window, paged
/// 50 rows at a time.
///
/// Rebuilds (and therefore resets to page 1) whenever the signed-in user, the
/// effective company, or the filter changes — so a company switch or a sign-out
/// can never leave another tenant's rows on screen.
///
/// Not autoDispose, for the same reason as [ActivityHistoryFilterNotifier]:
/// scrolling the section off-screen would otherwise re-bill a 50-document read
/// every time it scrolled back into view.
class ActivityHistoryController extends Notifier<ActivityHistoryState> {
  /// Rows shown per page.
  ///
  /// Every fetch asks for `pageSize + 1` and shows at most [pageSize]: the
  /// extra row is what PROVES a next page exists. Inferring it from
  /// `items.length == pageSize` instead would light up "Next" for a month
  /// holding exactly 50 (or 100, or 150) requests and land the user on an empty
  /// page captioned "No activity in this period" — a flat lie about an archive
  /// whose whole job is to be trustworthy.
  static const int pageSize = 50;

  /// Guards against a slow in-flight fetch overwriting a newer one (e.g. the
  /// user flips months while page 1 is still loading).
  int _generation = 0;

  /// Everything a fetch needs, resolved once per [build] from the watched
  /// providers. Snapshotting it here keeps [_load] free of any `ref` read that
  /// could disagree with the scope this page was started for.
  ({bool isAdmin, String companyId, DateRange window})? _scope;

  @override
  ActivityHistoryState build() {
    final user = ref.watch(currentUserProvider).valueOrNull;
    // Watched, not read: a change to either must reset the archive to page 1.
    final filter = ref.watch(activityHistoryFilterProvider);
    final companyId = ref.watch(dashboardCompanyIdProvider);

    // Invalidate anything still in flight for the previous scope, so a late
    // response can never paint the wrong company's (or ex-user's) rows.
    _generation++;
    _scope = null;

    if (user == null) return const ActivityHistoryState();

    final isAdmin = user.role.isAdmin;
    // A company-scoped role with no resolved company would issue a query that
    // can only ever be empty — skip the read entirely.
    if (!isAdmin && companyId.isEmpty) return const ActivityHistoryState();

    _scope =
        (isAdmin: isAdmin, companyId: companyId, window: filter.window);
    // NOTE: [_load] must not assign `state` before its first `await` — Riverpod
    // forbids mutating state during build, and the value returned below would
    // overwrite it anyway.
    unawaited(_load(const []));
    return const ActivityHistoryState(loading: true);
  }

  /// Advances one page, anchored on the oldest row currently shown.
  void nextPage() {
    final s = state;
    if (s.loading || !s.hasMore || s.items.isEmpty) return;
    final last = s.items.last;
    // An offline-optimistic row has no server timestamp yet and so cannot
    // anchor a cursor; refuse rather than silently restart the window.
    final at = last.createdAt;
    if (at == null) return;
    _goTo([...s.cursors, (at: at, id: last.id)]);
  }

  /// Steps back one page by popping the cursor that produced the current one.
  void previousPage() {
    final s = state;
    if (s.loading || s.cursors.isEmpty) return;
    _goTo(s.cursors.sublist(0, s.cursors.length - 1));
  }

  void _goTo(List<PeriodCursor> cursors) {
    // Guarded HERE, not inside [_load], so that _load can never assign `state`
    // before its first `await` — see the NOTE in [build].
    if (_scope == null) {
      state = const ActivityHistoryState();
      return;
    }
    state = ActivityHistoryState(loading: true, cursors: cursors);
    unawaited(_load(cursors));
  }

  /// MUST NOT touch `state` before its first `await`: [build] calls this
  /// synchronously, and Riverpod forbids mutating state during a build.
  Future<void> _load(List<PeriodCursor> cursors) async {
    final generation = _generation;
    final scope = _scope!;

    final before = cursors.isEmpty ? null : cursors.last;
    final repo = ref.read(requestRepositoryProvider);
    // One over pageSize — the extra row is the proof of a successor, never
    // rendered. See [pageSize].
    const fetchLimit = pageSize + 1;
    final result = scope.isAdmin
        ? await repo.fetchAllByPeriod(scope.window,
            limit: fetchLimit, before: before)
        : await repo.fetchByCompanyAndPeriod(scope.companyId, scope.window,
            limit: fetchLimit, before: before);

    if (generation != _generation) return; // Superseded by a newer request.

    state = result.when(
      ok: (rows) => ActivityHistoryState(
        items: rows.take(pageSize).toList(),
        cursors: cursors,
        hasMore: rows.length > pageSize,
      ),
      err: (failure) => ActivityHistoryState(
        cursors: cursors,
        failure: failure,
      ),
    );
  }
}

final activityHistoryControllerProvider =
    NotifierProvider<ActivityHistoryController, ActivityHistoryState>(
  ActivityHistoryController.new,
);
