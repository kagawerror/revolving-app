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
import 'package:rev_app/features/requests/presentation/conflict_worklist_body.dart';
import 'package:rev_app/features/requests/presentation/request_providers.dart';
import 'package:rev_app/features/sync/domain/optimistic_balance.dart';
import 'package:rev_app/features/sync/presentation/sync_providers.dart';

class _MockRepo extends Mock implements RequestRepository {}

const _incharge = AppUser(
  uid: 'i1',
  companyId: 'c1',
  role: UserRole.incharge,
  displayName: 'Ina',
  email: 'ina@acme.test',
);

FundRequest _conflict() => FundRequest(
      id: 'r1',
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: 'Ben',
      amount: Money.fromCentavos(50000),
      purpose: 'Supplies',
      proofImageUrl: '',
      status: RequestStatus.conflict,
      releaseState: 'conflict',
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_conflict());
    registerFallbackValue(RequestStatus.released);
  });

  /// Pumps a launcher whose body WATCHES currentUserProvider (so the auth stream
  /// is live before the sheet's action reads it) and opens the resolution sheet
  /// on tap. Uses a tall test window so the whole DraggableScrollableSheet is
  /// laid out and every action is hittable without manual scrolling.
  Future<void> pumpSheet(WidgetTester tester, _MockRepo repo) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          requestRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWith((ref) => Stream.value(_incharge)),
          // Healthy balance so the "can cover" hint renders; never gates.
          optimisticFundBalanceProvider.overrideWith(
              (ref, fundId) => const OptimisticBalance(100000)),
          // Fund stream resolves the display-only name threaded onto the
          // requestRejected notification (void path). Avoids touching real
          // Firestore via fundRepositoryProvider in this widget test.
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
          home: Consumer(
            builder: (context, ref, _) {
              // Keep the auth stream subscribed so the sheet's read() sees data.
              ref.watch(currentUserProvider);
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () =>
                        ConflictResolutionSheet.show(context, _conflict()),
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Re-release calls resolveConflict(to: released) after confirm',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.resolveConflict(
          request: any(named: 'request'),
          to: any(named: 'to'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => const Ok(null));

    await pumpSheet(tester, repo);

    // Tap the re-release primary action -> opens the confirm dialog.
    await tester.tap(find.widgetWithText(FilledButton, 'Re-release now'));
    await tester.pumpAndSettle();
    // Nothing called yet — the decision is behind the confirm.
    verifyNever(() => repo.resolveConflict(
        request: any(named: 'request'),
        to: any(named: 'to'),
        actorUid: any(named: 'actorUid')));

    // Confirm via the dialog's "Re-release" button.
    await tester.tap(find.widgetWithText(FilledButton, 'Re-release'));
    await tester.pumpAndSettle();

    final captured = verify(() => repo.resolveConflict(
          request: any(named: 'request'),
          to: captureAny(named: 'to'),
          actorUid: 'i1',
        )).captured;
    expect(captured.single, RequestStatus.released);
  });

  testWidgets('Void calls resolveConflict(to: rejected) after confirm',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.resolveConflict(
          request: any(named: 'request'),
          to: any(named: 'to'),
          actorUid: any(named: 'actorUid'),
          fundName: any(named: 'fundName'),
        )).thenAnswer((_) async => const Ok(null));

    await pumpSheet(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Void this release'));
    await tester.pumpAndSettle();
    verifyNever(() => repo.resolveConflict(
        request: any(named: 'request'),
        to: any(named: 'to'),
        actorUid: any(named: 'actorUid')));

    await tester.tap(find.widgetWithText(FilledButton, 'Void release'));
    await tester.pumpAndSettle();

    final captured = verify(() => repo.resolveConflict(
          request: any(named: 'request'),
          to: captureAny(named: 'to'),
          actorUid: 'i1',
          fundName: captureAny(named: 'fundName'),
        )).captured;
    expect(captured, [RequestStatus.rejected, 'Petty Cash']);
  });

  testWidgets('cancelling the confirm dialog moves no money', (tester) async {
    final repo = _MockRepo();
    await pumpSheet(tester, repo);

    await tester.tap(find.widgetWithText(FilledButton, 'Re-release now'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => repo.resolveConflict(
        request: any(named: 'request'),
        to: any(named: 'to'),
        actorUid: any(named: 'actorUid')));
  });
}
