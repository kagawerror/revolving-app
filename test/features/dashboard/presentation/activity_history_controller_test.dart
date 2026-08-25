import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/companies/presentation/admin_company_context_bar.dart';
import 'package:rev_app/features/dashboard/presentation/activity_history_providers.dart';
import 'package:rev_app/features/reports/domain/report_period.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_repository.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/request_providers.dart';

class _MockRepo extends Mock implements RequestRepository {}

AppUser _user(
  UserRole role,
  String companyId, {
  List<String> memberships = const [],
}) =>
    AppUser(
      uid: 'u',
      companyId: companyId,
      companyIds: memberships,
      role: role,
      displayName: 'n',
      email: 'e@x.com',
    );

FundRequest _req(String id, DateTime createdAt) => FundRequest(
      id: id,
      companyId: 'c1',
      fundId: 'f',
      createdByUid: 'u',
      beneficiaryName: 'B',
      amount: Money.fromCentavos(100),
      purpose: 'x',
      proofImageUrl: 'http://img',
      status: RequestStatus.released,
      createdAt: createdAt,
    );

/// What the repository hands back when a further page exists: `pageSize + 1`
/// rows. The controller shows [ActivityHistoryController.pageSize] of them and
/// treats the extra as proof of a successor.
List<FundRequest> _overflowingPage(int page) => _rows(page, _fetchLimit);

/// Exactly [ActivityHistoryController.pageSize] rows — a FULL page with NO
/// successor, since the repository had no `pageSize + 1`th row to give.
List<FundRequest> _exactlyFullPage(int page) =>
    _rows(page, ActivityHistoryController.pageSize);

List<FundRequest> _rows(int page, int count) => [
      for (var i = 0; i < count; i++)
        _req('p$page-$i', DateTime(2026, 6, 1).add(Duration(minutes: i))),
    ];

/// The controller always over-fetches by one.
const _fetchLimit = ActivityHistoryController.pageSize + 1;

void main() {
  setUpAll(() {
    registerFallbackValue(
      DateRange(start: DateTime(2000), endExclusive: DateTime(2000)),
    );
  });

  late _MockRepo repo;

  /// Frozen "now" so the default filter is deterministic: June 2026.
  DateTime now() => DateTime(2026, 6, 15, 9, 30);

  ProviderContainer container(AppUser user) {
    final c = ProviderContainer(overrides: [
      requestRepositoryProvider.overrideWithValue(repo),
      currentUserProvider.overrideWith((ref) => Stream.value(user)),
      activityHistoryClockProvider.overrideWithValue(now),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  /// Pumps until the controller settles out of its loading state.
  Future<ActivityHistoryState> settle(ProviderContainer c) async {
    await c.read(currentUserProvider.future);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      if (!c.read(activityHistoryControllerProvider).loading) break;
    }
    return c.read(activityHistoryControllerProvider);
  }

  setUp(() {
    repo = _MockRepo();
  });

  void stubCompany(List<List<FundRequest>> pages) {
    var call = 0;
    when(() => repo.fetchByCompanyAndPeriod(
          any(),
          any(),
          limit: any(named: 'limit'),
          before: any(named: 'before'),
        )).thenAnswer((_) async {
      final page = call < pages.length ? pages[call] : const <FundRequest>[];
      call++;
      return Ok(page);
    });
  }

  test('defaults to the current month/year from the injected clock', () {
    final c = container(_user(UserRole.incharge, 'c1'));
    final filter = c.read(activityHistoryFilterProvider);
    expect(filter.month, 6);
    expect(filter.year, 2026);
    expect(filter.window,
        periodWindow(PeriodGranularity.month, DateTime(2026, 6, 1)));
  });

  test('year options run from the current year backwards', () {
    final c = container(_user(UserRole.incharge, 'c1'));
    expect(c.read(activityHistoryYearsProvider), [2026, 2025, 2024, 2023, 2022]);
  });

  test('a short first page means one page: no pagination, no next', () async {
    stubCompany([
      [_req('a', DateTime(2026, 6, 3)), _req('b', DateTime(2026, 6, 2))],
    ]);
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(activityHistoryControllerProvider, (_, _) {});

    final s = await settle(c);
    expect(s.items.map((r) => r.id), ['a', 'b']);
    expect(s.hasMore, isFalse);
    expect(s.canGoPrevious, isFalse);
    expect(s.isPaginated, isFalse);
    expect(s.pageNumber, 1);
  });

  test('an over-full page trims to pageSize and flags hasMore', () async {
    stubCompany([_overflowingPage(1)]);
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(activityHistoryControllerProvider, (_, _) {});

    final s = await settle(c);
    // The pageSize + 1'th row is the successor PROOF, never rendered.
    expect(s.items, hasLength(ActivityHistoryController.pageSize));
    expect(s.hasMore, isTrue);
    expect(s.isPaginated, isTrue);
    expect(s.canGoPrevious, isFalse);
  });

  test(
      'a month holding EXACTLY pageSize requests has no successor: Next stays '
      'off and no empty page is reachable', () async {
    stubCompany([_exactlyFullPage(1)]);
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(activityHistoryControllerProvider, (_, _) {});

    final s = await settle(c);
    expect(s.items, hasLength(ActivityHistoryController.pageSize));
    expect(s.hasMore, isFalse,
        reason: 'the repo had no pageSize+1th row to give');
    expect(s.canGoNext, isFalse);
    expect(s.isPaginated, isFalse);

    // And nextPage() is inert, so the user cannot reach a false "No activity".
    c.read(activityHistoryControllerProvider.notifier).nextPage();
    await settle(c);
    verify(() => repo.fetchByCompanyAndPeriod(any(), any(),
        limit: any(named: 'limit'), before: any(named: 'before'))).called(1);
  });

  test('every fetch over-fetches by exactly one row', () async {
    stubCompany([_overflowingPage(1)]);
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(activityHistoryControllerProvider, (_, _) {});
    await settle(c);

    verify(() => repo.fetchByCompanyAndPeriod(any(), any(),
        limit: _fetchLimit, before: any(named: 'before'))).called(1);
  });

  test('nextPage pushes a (createdAt, id) cursor from the last rendered row',
      () async {
    final page1 = _overflowingPage(1);
    stubCompany([page1, [_req('tail', DateTime(2026, 6, 1))]]);
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(activityHistoryControllerProvider, (_, _) {});
    final first = await settle(c);

    // The anchor is the last VISIBLE row, not the trimmed-off proof row.
    final anchor = first.items.last;
    expect(anchor.id, isNot(page1.last.id));

    c.read(activityHistoryControllerProvider.notifier).nextPage();
    final s = await settle(c);

    expect(s.items.map((r) => r.id), ['tail']);
    expect(s.cursors, [(at: anchor.createdAt, id: anchor.id)]);
    expect(s.pageNumber, 2);
    expect(s.canGoPrevious, isTrue);
    expect(s.hasMore, isFalse);

    final captured = verify(() => repo.fetchByCompanyAndPeriod(
          'c1',
          any(),
          limit: _fetchLimit,
          before: captureAny(named: 'before'),
        )).captured;
    expect(captured, [null, (at: anchor.createdAt, id: anchor.id)]);
  });

  test('previousPage pops the cursor stack back to page 1', () async {
    final page1 = _overflowingPage(1);
    stubCompany([page1, _overflowingPage(2), page1]);
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(activityHistoryControllerProvider, (_, _) {});
    await settle(c);

    c.read(activityHistoryControllerProvider.notifier).nextPage();
    await settle(c);
    expect(c.read(activityHistoryControllerProvider).cursors, hasLength(1));

    c.read(activityHistoryControllerProvider.notifier).previousPage();
    final s = await settle(c);
    expect(s.cursors, isEmpty);
    expect(s.pageNumber, 1);
    expect(s.canGoPrevious, isFalse);
  });

  test('previousPage on page 1 is a no-op (no extra fetch)', () async {
    stubCompany([
      [_req('a', DateTime(2026, 6, 3))],
    ]);
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(activityHistoryControllerProvider, (_, _) {});
    await settle(c);

    c.read(activityHistoryControllerProvider.notifier).previousPage();
    await settle(c);

    verify(() => repo.fetchByCompanyAndPeriod(any(), any(),
        limit: any(named: 'limit'), before: any(named: 'before'))).called(1);
  });

  test('changing the filter resets to page 1 and requeries the new window',
      () async {
    stubCompany([
      _overflowingPage(1),
      _overflowingPage(2),
      [_req('mar', DateTime(2026, 3, 4))],
    ]);
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(activityHistoryControllerProvider, (_, _) {});
    await settle(c);

    // Walk to page 2 so the reset is observable.
    c.read(activityHistoryControllerProvider.notifier).nextPage();
    await settle(c);
    expect(c.read(activityHistoryControllerProvider).cursors, hasLength(1));

    c.read(activityHistoryFilterProvider.notifier).setMonth(3);
    final s = await settle(c);

    expect(s.cursors, isEmpty, reason: 'filter change must reset paging');
    expect(s.pageNumber, 1);
    expect(s.items.map((r) => r.id), ['mar']);

    final windows = verify(() => repo.fetchByCompanyAndPeriod(
          any(),
          captureAny(),
          limit: any(named: 'limit'),
          before: any(named: 'before'),
        )).captured;
    expect(windows.last,
        periodWindow(PeriodGranularity.month, DateTime(2026, 3, 1)));
  });

  test('changing the year also resets and requeries', () async {
    stubCompany([
      [_req('a', DateTime(2026, 6, 3))],
      [_req('b', DateTime(2024, 6, 3))],
    ]);
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(activityHistoryControllerProvider, (_, _) {});
    await settle(c);

    c.read(activityHistoryFilterProvider.notifier).setYear(2024);
    final s = await settle(c);

    expect(s.items.map((r) => r.id), ['b']);
    final windows = verify(() => repo.fetchByCompanyAndPeriod(
          any(),
          captureAny(),
          limit: any(named: 'limit'),
          before: any(named: 'before'),
        )).captured;
    expect(windows.last,
        periodWindow(PeriodGranularity.month, DateTime(2024, 6, 1)));
  });

  test('admins query across every company (fetchAllByPeriod)', () async {
    when(() => repo.fetchAllByPeriod(any(),
            limit: any(named: 'limit'), before: any(named: 'before')))
        .thenAnswer((_) async => Ok([_req('all', DateTime(2026, 6, 3))]));

    final c = container(_user(UserRole.admin, ''));
    c.listen(activityHistoryControllerProvider, (_, _) {});
    final s = await settle(c);

    expect(s.items.map((r) => r.id), ['all']);
    verifyNever(() => repo.fetchByCompanyAndPeriod(any(), any(),
        limit: any(named: 'limit'), before: any(named: 'before')));
  });

  // --- Scope resets ---------------------------------------------------------
  // The non-autoDispose design leans on these: nothing tears the controller
  // down, so it MUST clear itself when the session or company changes.

  test('signing out clears the rendered rows', () async {
    stubCompany([
      [_req('a', DateTime(2026, 6, 3))],
    ]);
    final users = StreamController<AppUser?>();
    addTearDown(users.close);
    final c = ProviderContainer(overrides: [
      requestRepositoryProvider.overrideWithValue(repo),
      currentUserProvider.overrideWith((ref) => users.stream),
      activityHistoryClockProvider.overrideWithValue(now),
    ]);
    addTearDown(c.dispose);
    c.listen(activityHistoryControllerProvider, (_, _) {});

    users.add(_user(UserRole.incharge, 'c1'));
    await settle(c);
    expect(c.read(activityHistoryControllerProvider).items, isNotEmpty);

    users.add(null);
    final s = await settle(c);
    expect(s.items, isEmpty, reason: 'an ex-session must leave no rows behind');
    expect(s.loading, isFalse);
    expect(s.cursors, isEmpty);
  });

  test('switching the active company re-queries and swaps the rows', () async {
    when(() => repo.fetchByCompanyAndPeriod(
          any(),
          any(),
          limit: any(named: 'limit'),
          before: any(named: 'before'),
        )).thenAnswer((inv) async {
      final companyId = inv.positionalArguments[0] as String;
      return Ok([_req('row-$companyId', DateTime(2026, 6, 3))]);
    });

    final c = container(
      _user(UserRole.incharge, 'cA', memberships: const ['cA', 'cB']),
    );
    c.listen(activityHistoryControllerProvider, (_, _) {});
    await settle(c);
    expect(c.read(activityHistoryControllerProvider).items.single.id, 'row-cA');

    c.read(adminActiveCompanyProvider.notifier).state = 'cB';
    final s = await settle(c);
    expect(s.items.single.id, 'row-cB',
        reason: 'no other tenant rows may survive a company switch');
    expect(s.cursors, isEmpty, reason: 'company switch resets to page 1');
  });

  // --- Future windows -------------------------------------------------------

  test('the year dropdown never offers a future year', () {
    final c = container(_user(UserRole.incharge, 'c1'));
    expect(c.read(activityHistoryYearsProvider).first, 2026);
    expect(c.read(activityHistoryYearsProvider).every((y) => y <= 2026), isTrue);
  });

  test('the month dropdown stops at the current month in the current year', () {
    final c = container(_user(UserRole.incharge, 'c1'));
    // Default filter year is 2026 (= "now"), so months stop at June.
    expect(c.read(activityHistoryMonthsProvider), [1, 2, 3, 4, 5, 6]);
  });

  test('a past year offers all twelve months', () {
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(activityHistoryMonthsProvider, (_, _) {});
    c.read(activityHistoryFilterProvider.notifier).setYear(2024);
    expect(c.read(activityHistoryMonthsProvider), hasLength(12));
  });

  test('moving to the current year clamps a month that would land in the future',
      () async {
    stubCompany([
      [_req('a', DateTime(2024, 12, 3))],
    ]);
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(activityHistoryFilterProvider, (_, _) {});

    // December 2024 is legal...
    c.read(activityHistoryFilterProvider.notifier).setYear(2024);
    c.read(activityHistoryFilterProvider.notifier).setMonth(12);
    expect(c.read(activityHistoryFilterProvider).month, 12);

    // ...but December 2026 has not happened yet, so it clamps to June 2026.
    c.read(activityHistoryFilterProvider.notifier).setYear(2026);
    final f = c.read(activityHistoryFilterProvider);
    expect(f.year, 2026);
    expect(f.month, 6);
  });

  test('setMonth refuses to select a future month', () {
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(activityHistoryFilterProvider, (_, _) {});
    c.read(activityHistoryFilterProvider.notifier).setMonth(11);
    // Clamped back to the current month rather than querying an empty future.
    expect(c.read(activityHistoryFilterProvider).month, 6);
  });

  test('a company-scoped role with no resolved company never queries', () async {
    stubCompany([
      [_req('a', DateTime(2026, 6, 3))],
    ]);
    final c = container(_user(UserRole.incharge, ''));
    c.listen(activityHistoryControllerProvider, (_, _) {});

    final s = await settle(c);
    expect(s.items, isEmpty);
    expect(s.loading, isFalse, reason: 'must not hang on a spinner');
    verifyNever(() => repo.fetchByCompanyAndPeriod(any(), any(),
        limit: any(named: 'limit'), before: any(named: 'before')));
    verifyNever(() => repo.fetchAllByPeriod(any(),
        limit: any(named: 'limit'), before: any(named: 'before')));
  });

  test('a repository failure surfaces on the state and clears the rows',
      () async {
    when(() => repo.fetchByCompanyAndPeriod(any(), any(),
            limit: any(named: 'limit'), before: any(named: 'before')))
        .thenAnswer((_) async => const Err(UnexpectedFailure('boom')));

    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(activityHistoryControllerProvider, (_, _) {});
    final s = await settle(c);

    expect(s.failure, isA<UnexpectedFailure>());
    expect(s.items, isEmpty);
    expect(s.isPaginated, isFalse);
  });
}
