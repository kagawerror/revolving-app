import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/core/theme/app_accents.dart';
import 'package:rev_app/core/theme/theme_controller.dart';
import 'package:rev_app/features/dashboard/domain/dashboard_summary.dart';
import 'package:rev_app/features/dashboard/presentation/dashboard_body.dart';
import 'package:rev_app/features/dashboard/presentation/dashboard_providers.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

FundRequest _request() => FundRequest(
      id: 'r1',
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: 'Maria Santos',
      amount: Money.fromCentavos(250000), // ₱2,500.00
      purpose: 'Fuel reimbursement',
      proofImageUrl: 'https://example.test/proof.jpg',
      status: RequestStatus.released,
      createdAt: DateTime(2026, 6, 13, 10, 0),
    );

const _emptySummary = DashboardSummary(
  totals: FundTotals(
    totalBudget: Money.zero,
    totalAvailable: Money.zero,
    fundCount: 0,
    lowFundCount: 0,
    replenishingFundCount: 0,
  ),
  pendingRequestCount: 0,
  pendingReplenishmentCount: 0,
);

void main() {
  testWidgets('tapping a recent-activity row opens the detail sheet',
      (tester) async {
    final request = _request();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeControllerProvider.overrideWithValue(
            ThemeState(
              mode: ThemeMode.light,
              seed: AppAccents.byId(AppAccents.defaultId).seed,
            ),
          ),
          dashboardSummaryProvider.overrideWithValue(
            const AsyncValue.data(_emptySummary),
          ),
          dashboardFundsProvider.overrideWithValue(
            const AsyncValue.data([]),
          ),
          recentRequestsProvider.overrideWith(
            (ref) => Stream.value([request]),
          ),
          dashboardPendingPartialByRequestProvider.overrideWithValue(
            {request.id: Money.fromCentavos(40000)}, // ₱400 pending partial
          ),
          companyNamesProvider.overrideWithValue(const {}),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DashboardBody()),
        ),
      ),
    );

    // Let the recent-requests stream + summary settle into the data branch.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The recent-activity section sits at the bottom of the dashboard's
    // outer ListView; scroll it into view so its (lazily built) tile renders.
    await tester.dragUntilVisible(
      find.text('Maria Santos'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pump();

    // The recent-activity row for our request is on screen.
    expect(find.text('Maria Santos'), findsOneWidget);

    // Tapping it opens the read-only detail sheet.
    await tester.tap(find.text('Maria Santos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The sheet's header label identifies the glance view; the beneficiary
    // name now appears in both the (animating-out) tile and the sheet header.
    expect(find.text('Request details'), findsOneWidget);
    expect(find.text('Maria Santos'), findsWidgets);
    // Sheet summary card shows the full amount.
    expect(find.text(Money.fromCentavos(250000).format()), findsWidgets);
  });
}
