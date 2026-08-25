import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/core/theme/app_accents.dart';
import 'package:rev_app/core/theme/theme_controller.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/dashboard/domain/dashboard_summary.dart';
import 'package:rev_app/features/dashboard/presentation/activity_history_providers.dart';
import 'package:rev_app/features/dashboard/presentation/dashboard_body.dart';
import 'package:rev_app/features/dashboard/presentation/dashboard_providers.dart';
import 'package:rev_app/features/reports/domain/report_period.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_repository.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/request_providers.dart';

class _MockRepo extends Mock implements RequestRepository {}

/// Replaces the real controller so a page shape (rows + hasMore + cursor depth)
/// can be pinned exactly, without seeding 50 rows through a repository.
class _StubController extends ActivityHistoryController {
  _StubController(this._initial);

  final ActivityHistoryState _initial;
  int nextCalls = 0;
  int previousCalls = 0;

  @override
  ActivityHistoryState build() => _initial;

  @override
  void nextPage() => nextCalls++;

  @override
  void previousPage() => previousCalls++;
}

const _emptySummary = DashboardSummary(
  totals: FundTotals(
    totalBudget: Money.zero,
    totalAvailable: Money.zero,
    fundCount: 0,
    lowFundCount: 0,
    replenishingFundCount: 0,
    totalAdjustmentsCentavos: 0,
  ),
  pendingRequestCount: 0,
  pendingReplenishmentCount: 0,
);

AppUser _incharge() => const AppUser(
      uid: 'u',
      companyId: 'c1',
      companyIds: [],
      role: UserRole.incharge,
      displayName: 'n',
      email: 'e@x.com',
    );

FundRequest _req(String id, String name, DateTime createdAt) => FundRequest(
      id: id,
      companyId: 'c1',
      fundId: 'f',
      createdByUid: 'u',
      beneficiaryName: name,
      amount: Money.fromCentavos(100),
      purpose: 'Fuel',
      proofImageUrl: 'http://img',
      status: RequestStatus.released,
      createdAt: createdAt,
    );

DateTime _now() => DateTime(2026, 6, 15, 9, 30);

Widget _app(List<Override> extra) => ProviderScope(
      overrides: [
        themeControllerProvider.overrideWithValue(
          ThemeState(
            mode: ThemeMode.light,
            seed: AppAccents.byId(AppAccents.defaultId).seed,
          ),
        ),
        dashboardSummaryProvider
            .overrideWithValue(const AsyncValue.data(_emptySummary)),
        dashboardFundsProvider.overrideWithValue(const AsyncValue.data([])),
        recentRequestsProvider.overrideWith((ref) => Stream.value([])),
        dashboardPendingPartialByRequestProvider.overrideWithValue(const {}),
        companyNamesProvider.overrideWithValue(const {}),
        activityHistoryClockProvider.overrideWithValue(_now),
        currentUserProvider.overrideWith((ref) => Stream.value(_incharge())),
        ...extra,
      ],
      child: const MaterialApp(home: Scaffold(body: DashboardBody())),
    );

/// Scrolls the dashboard until [finder] is on screen.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(Scrollable).first,
    const Offset(0, -260),
  );
  await tester.pump();
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      DateRange(start: DateTime(2000), endExclusive: DateTime(2000)),
    );
  });

  testWidgets('a single short page renders rows but no pagination controls',
      (tester) async {
    await tester.pumpWidget(_app([
      activityHistoryControllerProvider.overrideWith(
        () => _StubController(
          ActivityHistoryState(
            items: [_req('a', 'Maria Santos', DateTime(2026, 6, 13))],
          ),
        ),
      ),
    ]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await _scrollTo(tester, find.text('Maria Santos'));

    expect(find.text('Activity history'), findsOneWidget);
    expect(find.text('Maria Santos'), findsOneWidget);
    // <= one page: the controls are not rendered at all.
    expect(find.text('Previous'), findsNothing);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('page 1 of many: Next is enabled, Previous is disabled',
      (tester) async {
    await tester.pumpWidget(_app([
      activityHistoryControllerProvider.overrideWith(
        () => _StubController(
          ActivityHistoryState(
            items: [_req('a', 'Maria Santos', DateTime(2026, 6, 13))],
            hasMore: true,
          ),
        ),
      ),
    ]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await _scrollTo(tester, find.text('Next'));

    expect(find.text('Page 1'), findsOneWidget);
    final prev = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Previous'),
    );
    final next = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Next'),
    );
    expect(prev.onPressed, isNull, reason: 'no page before page 1');
    expect(next.onPressed, isNotNull);
  });

  testWidgets('last page: Previous is enabled, Next is disabled', (tester) async {
    await tester.pumpWidget(_app([
      activityHistoryControllerProvider.overrideWith(
        () => _StubController(
          ActivityHistoryState(
            items: [_req('a', 'Maria Santos', DateTime(2026, 6, 13))],
            cursors: [(at: DateTime(2026, 6, 14), id: 'prev')],
          ),
        ),
      ),
    ]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await _scrollTo(tester, find.text('Next'));

    expect(find.text('Page 2'), findsOneWidget);
    final prev = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Previous'),
    );
    final next = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Next'),
    );
    expect(prev.onPressed, isNotNull);
    expect(next.onPressed, isNull, reason: 'the short page ends the archive');
  });

  testWidgets('tapping Next / Previous drives the controller', (tester) async {
    final stub = _StubController(
      ActivityHistoryState(
        items: [_req('a', 'Maria Santos', DateTime(2026, 6, 13))],
        cursors: [(at: DateTime(2026, 6, 14), id: 'prev')],
        hasMore: true,
      ),
    );
    await tester.pumpWidget(_app([
      activityHistoryControllerProvider.overrideWith(() => stub),
    ]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await _scrollTo(tester, find.text('Next'));

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Previous'));
    await tester.pump();

    expect(stub.nextCalls, 1);
    expect(stub.previousCalls, 1);
  });

  testWidgets('every row shows its created date', (tester) async {
    await tester.pumpWidget(_app([
      activityHistoryControllerProvider.overrideWith(
        () => _StubController(
          ActivityHistoryState(
            items: [
              _req('a', 'Maria Santos', DateTime(2026, 6, 13)),
              _req('b', 'Jose Rizal', DateTime(2026, 6, 2)),
            ],
          ),
        ),
      ),
    ]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await _scrollTo(tester, find.text('Maria Santos'));

    expect(find.textContaining('Created 13 Jun 2026'), findsOneWidget);
    expect(find.textContaining('Created 2 Jun 2026'), findsOneWidget);
  });

  testWidgets(
      'the month + year dropdowns render and changing the month refetches '
      'the new window', (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchByCompanyAndPeriod(any(), any(),
            limit: any(named: 'limit'), before: any(named: 'before')))
        .thenAnswer((_) async => Ok([_req('a', 'Maria Santos', DateTime(2026, 6, 13))]));

    await tester.pumpWidget(_app([
      requestRepositoryProvider.overrideWithValue(repo),
    ]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Both dropdowns default to the injected clock's month/year.
    await _scrollTo(tester, find.byKey(const Key('activityHistoryMonth')));
    expect(find.text('June'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('activityHistoryMonth')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('March').last);
    await tester.pumpAndSettle();

    final windows = verify(() => repo.fetchByCompanyAndPeriod(
          'c1',
          captureAny(),
          // Over-fetched by one: the extra row proves whether a next page
          // exists. See [ActivityHistoryController.pageSize].
          limit: ActivityHistoryController.pageSize + 1,
          before: any(named: 'before'),
        )).captured;
    expect(windows.last,
        periodWindow(PeriodGranularity.month, DateTime(2026, 3, 1)));
  });
}
