import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/presentation/replenishment_providers.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_repository.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/post_release_review_body.dart';
import 'package:rev_app/features/requests/presentation/request_detail_screen.dart';
import 'package:rev_app/features/requests/presentation/request_providers.dart';

class _MockRepo extends Mock implements RequestRepository {}

const _approver = AppUser(
  uid: 'm1',
  companyId: 'c1',
  role: UserRole.ceo,
  displayName: 'Cleo',
  email: 'cleo@acme.test',
);

FundRequest _released() => FundRequest(
      id: 'r1',
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: 'Ben',
      amount: Money.fromCentavos(50000),
      purpose: 'Supplies',
      // Empty image URLs so there is no perpetual CachedNetworkImage spinner —
      // keeps pumpAndSettle from timing out; the action row is what we exercise.
      proofImageUrl: '',
      status: RequestStatus.released,
    );

void main() {
  setUpAll(() => registerFallbackValue(_released()));

  Future<void> pumpDetail(WidgetTester tester, _MockRepo repo) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          requestRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWith((ref) => Stream.value(_approver)),
          // Drives pendingPartialByRequestProvider to empty (no breakdown card).
          pendingReplenishmentsProvider
              .overrideWith((ref) => Stream.value(const <Replenishment>[])),
        ],
        child: MaterialApp(home: RequestDetailScreen(request: _released())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Dispute passes the REAL collected reason (not a hard-coded string)',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.dispute(
          request: any(named: 'request'),
          actorUid: any(named: 'actorUid'),
          reason: any(named: 'reason'),
        )).thenAnswer((_) async => const Ok(null));

    await pumpDetail(tester, repo);

    // Open the dispute reason sheet.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Dispute'));
    await tester.pumpAndSettle();
    expect(find.byType(DisputeReasonSheet), findsOneWidget);

    // No call before a reason is entered + submitted.
    verifyNever(() => repo.dispute(
        request: any(named: 'request'),
        actorUid: any(named: 'actorUid'),
        reason: any(named: 'reason')));

    // Enter a real reason; submit enables only when non-empty.
    const reason = 'Amount does not match the receipt';
    await tester.enterText(find.byType(TextField), reason);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Submit dispute'));
    await tester.pumpAndSettle();

    final captured = verify(() => repo.dispute(
          request: any(named: 'request'),
          actorUid: 'm1',
          reason: captureAny(named: 'reason'),
        )).captured;
    expect(captured.single, reason);
    expect(captured.single, isNot('Disputed by approver'));
  });

  testWidgets('Acknowledge is behind a confirmation dialog', (tester) async {
    final repo = _MockRepo();
    when(() => repo.acknowledgePostRelease(
          request: any(named: 'request'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => const Ok(null));

    await pumpDetail(tester, repo);

    await tester.tap(find.widgetWithText(FilledButton, 'Acknowledge'));
    await tester.pumpAndSettle();
    // Confirm dialog up; nothing called yet.
    verifyNever(() => repo.acknowledgePostRelease(
        request: any(named: 'request'), actorUid: any(named: 'actorUid')));

    // Confirm via the dialog's Acknowledge button (the second one in the tree).
    await tester.tap(find.widgetWithText(FilledButton, 'Acknowledge').last);
    await tester.pumpAndSettle();

    verify(() => repo.acknowledgePostRelease(
        request: any(named: 'request'), actorUid: 'm1')).called(1);
  });
}
