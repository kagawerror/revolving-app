import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_repository.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/request_providers.dart';
import 'package:rev_app/features/requests/presentation/widgets/reject_request_sheet.dart';
import 'package:rev_app/features/requests/presentation/widgets/request_row_action.dart';
import 'package:rev_app/features/sync/presentation/sync_providers.dart';

/// The trailing action on an incharge worklist row. A `created` row now offers
/// BOTH outcomes — release the cash, or reject a request created by mistake —
/// because until release there is nothing to un-deduct.
class _MockRepo extends Mock implements RequestRepository {}

const _incharge = AppUser(
  uid: 'i1',
  companyId: 'c1',
  role: UserRole.incharge,
  displayName: 'Ina',
  email: 'ina@acme.test',
);

const _employee = AppUser(
  uid: 'e1',
  companyId: 'c1',
  role: UserRole.employee,
  displayName: 'Eve',
  email: 'eve@acme.test',
);

FundRequest _request(RequestStatus status) => FundRequest(
      id: 'r1',
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: 'Ben',
      amount: Money.fromCentavos(50000),
      purpose: 'Supplies',
      proofImageUrl: '',
      status: status,
    );

void main() {
  setUpAll(() => registerFallbackValue(_request(RequestStatus.created)));

  Future<void> pumpAction(
    WidgetTester tester,
    _MockRepo repo, {
    AppUser user = _incharge,
    RequestStatus status = RequestStatus.created,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          requestRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWith((ref) => Stream.value(user)),
          fundByIdProvider.overrideWith((ref, fundId) => Stream.value(
                Fund(
                  id: fundId,
                  companyId: 'c1',
                  name: 'Petty Cash',
                  originalBudget: Money.fromCentavos(10000000),
                  availableBalance: Money.fromCentavos(100000),
                  lowBalanceThresholdPct: 3,
                  status: FundStatus.active,
                ),
              )),
        ],
        child: MaterialApp(
          home: Scaffold(body: RequestRowAction(request: _request(status))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a created row offers both Release and Reject', (tester) async {
    await pumpAction(tester, _MockRepo());

    expect(find.widgetWithText(FilledButton, 'Release'), findsOneWidget);
    expect(find.byTooltip('Reject request'), findsOneWidget);
  });

  testWidgets('a conflict row offers Release but NOT Reject', (tester) async {
    // A conflict is an already-released overdraft: its rejection path is
    // resolveConflict (which re-validates money), not rejectBeforeRelease.
    await pumpAction(tester, _MockRepo(), status: RequestStatus.conflict);

    expect(find.widgetWithText(FilledButton, 'Release'), findsOneWidget);
    expect(find.byTooltip('Reject request'), findsNothing);
  });

  testWidgets('a released row offers neither — it falls back to the pill',
      (tester) async {
    await pumpAction(tester, _MockRepo(), status: RequestStatus.released);

    expect(find.widgetWithText(FilledButton, 'Release'), findsNothing);
    expect(find.byTooltip('Reject request'), findsNothing);
  });

  testWidgets('a non-custodian gets no actions at all', (tester) async {
    await pumpAction(tester, _MockRepo(), user: _employee);

    expect(find.widgetWithText(FilledButton, 'Release'), findsNothing);
    expect(find.byTooltip('Reject request'), findsNothing);
  });

  testWidgets('Reject opens the sheet and passes the collected reason',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.rejectBeforeRelease(
          request: any(named: 'request'),
          actorUid: any(named: 'actorUid'),
          reason: any(named: 'reason'),
          actorName: any(named: 'actorName'),
          fundName: any(named: 'fundName'),
        )).thenAnswer((_) async => const Ok(null));

    await pumpAction(tester, repo);

    await tester.tap(find.byTooltip('Reject request'));
    await tester.pumpAndSettle();
    expect(find.byType(RejectRequestSheet), findsOneWidget);

    const reason = 'Created by mistake — duplicate of R-1042.';
    await tester.enterText(find.byType(TextField), reason);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reject request'));
    await tester.pumpAndSettle();

    final captured = verify(() => repo.rejectBeforeRelease(
          request: any(named: 'request'),
          actorUid: 'i1',
          reason: captureAny(named: 'reason'),
          actorName: any(named: 'actorName'),
          fundName: captureAny(named: 'fundName'),
        )).captured;
    expect(captured.first, reason);
    // The denormalized display name rides along for the approvers' alert row.
    expect(captured.last, 'Petty Cash');
  });
}
