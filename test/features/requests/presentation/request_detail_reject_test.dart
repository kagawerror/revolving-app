import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/presentation/replenishment_providers.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_repository.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/request_detail_screen.dart';
import 'package:rev_app/features/requests/presentation/request_providers.dart';
import 'package:rev_app/features/requests/presentation/widgets/reject_request_sheet.dart';
import 'package:rev_app/features/sync/presentation/sync_providers.dart';

/// The incharge's escape hatch on the request detail screen: reject a request
/// that is still "To release" (`created`) — nothing to un-deduct.
class _MockRepo extends Mock implements RequestRepository {}

const _incharge = AppUser(
  uid: 'i1',
  companyId: 'c1',
  role: UserRole.incharge,
  displayName: 'Ina',
  email: 'ina@acme.test',
);

const _approver = AppUser(
  uid: 'm1',
  companyId: 'c1',
  role: UserRole.ceo,
  displayName: 'Cleo',
  email: 'cleo@acme.test',
);

FundRequest _request(RequestStatus status) => FundRequest(
      id: 'r1',
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: 'Ben',
      amount: Money.fromCentavos(50000),
      purpose: 'Supplies',
      // Empty so no CachedNetworkImage spinner stalls pumpAndSettle.
      proofImageUrl: '',
      status: status,
    );

void main() {
  setUpAll(() => registerFallbackValue(_request(RequestStatus.created)));

  Future<void> pumpDetail(
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
          pendingReplenishmentsProvider
              .overrideWith((ref) => Stream.value(const <Replenishment>[])),
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
        child: MaterialApp(home: RequestDetailScreen(request: _request(status))),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('incharge sees Reject on a still-created request',
      (tester) async {
    await pumpDetail(tester, _MockRepo());

    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsOneWidget);
  });

  testWidgets('Reject is NOT offered once the request is released',
      (tester) async {
    await pumpDetail(tester, _MockRepo(), status: RequestStatus.released);

    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsNothing);
  });

  testWidgets('an approver does not get the incharge Reject action',
      (tester) async {
    await pumpDetail(tester, _MockRepo(), user: _approver);

    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsNothing);
  });

  testWidgets('Reject goes through the sheet and passes the collected reason',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.rejectBeforeRelease(
          request: any(named: 'request'),
          actorUid: any(named: 'actorUid'),
          reason: any(named: 'reason'),
          actorName: any(named: 'actorName'),
          fundName: any(named: 'fundName'),
        )).thenAnswer((_) async => const Ok(null));

    await pumpDetail(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pumpAndSettle();
    expect(find.byType(RejectRequestSheet), findsOneWidget);

    // Nothing is called until a valid reason is submitted.
    verifyNever(() => repo.rejectBeforeRelease(
          request: any(named: 'request'),
          actorUid: any(named: 'actorUid'),
          reason: any(named: 'reason'),
          actorName: any(named: 'actorName'),
          fundName: any(named: 'fundName'),
        ));

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
          fundName: any(named: 'fundName'),
        )).captured;
    expect(captured.single, reason);
  });

  testWidgets('cancelling the sheet calls nothing', (tester) async {
    final repo = _MockRepo();
    await pumpDetail(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Keep request'));
    await tester.pumpAndSettle();

    verifyNever(() => repo.rejectBeforeRelease(
          request: any(named: 'request'),
          actorUid: any(named: 'actorUid'),
          reason: any(named: 'reason'),
          actorName: any(named: 'actorName'),
          fundName: any(named: 'fundName'),
        ));
  });
}
