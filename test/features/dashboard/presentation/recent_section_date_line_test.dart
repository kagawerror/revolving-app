import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/core/theme/app_accents.dart';
import 'package:rev_app/core/theme/theme_controller.dart';
import 'package:rev_app/features/dashboard/domain/dashboard_summary.dart';
import 'package:rev_app/features/dashboard/presentation/activity_history_providers.dart';
import 'package:rev_app/features/dashboard/presentation/dashboard_body.dart';
import 'package:rev_app/features/dashboard/presentation/dashboard_providers.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

/// Regression cover for a behavior change to already-shipped UI: `AppListTile`
/// used to clip every subtitle to ONE line, so the `'purpose\ndate'` subtitle
/// that `recentDateLine` builds had its date silently thrown away and the
/// Recent-activity list never actually showed a date. `_RecentTile` now passes
/// `subtitleMaxLines: 2`. (`AppListTile`'s own default stays 1 — every other
/// call site is single-line and unaffected.)
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

FundRequest _released() => FundRequest(
      id: 'r1',
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: 'Maria Santos',
      amount: Money.fromCentavos(250000),
      purpose: 'Fuel reimbursement',
      proofImageUrl: 'https://example.test/proof.jpg',
      status: RequestStatus.released,
      createdAt: DateTime(2026, 6, 13, 10, 0),
      releasedAt: DateTime(2026, 6, 14, 9, 0),
    );

void main() {
  testWidgets(
      'the Recent-activity tile renders its created/released date line instead '
      'of clipping it away', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
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
          recentRequestsProvider.overrideWith((ref) => Stream.value([_released()])),
          dashboardPendingPartialByRequestProvider.overrideWithValue(const {}),
          companyNamesProvider.overrideWithValue(const {}),
          // Keep the Activity-history section inert; this test is about the
          // pre-existing Recent-activity list.
          activityHistoryControllerProvider
              .overrideWith(ActivityHistoryController.new),
        ],
        child: const MaterialApp(home: Scaffold(body: DashboardBody())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.dragUntilVisible(
      find.text('Maria Santos'),
      find.byType(Scrollable).first,
      const Offset(0, -260),
    );
    await tester.pump();

    final subtitle = find.textContaining('Created 13 Jun 2026');
    expect(subtitle, findsOneWidget);

    final widget = tester.widget<Text>(subtitle);
    expect(widget.data, contains('Fuel reimbursement'));
    expect(widget.data, contains('\n'), reason: 'purpose + date are two lines');
    expect(widget.data, contains('Released 14 Jun 2026'));
    expect(widget.maxLines, 2);

    // Nothing was ellipsized away: the paragraph fit inside its maxLines.
    final paragraph = tester.renderObject<RenderParagraph>(subtitle);
    expect(paragraph.didExceedMaxLines, isFalse);
  });
}
