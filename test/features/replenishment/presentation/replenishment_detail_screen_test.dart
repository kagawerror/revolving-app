import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_repository.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';
import 'package:rev_app/features/replenishment/presentation/replenishment_detail_screen.dart';
import 'package:rev_app/features/replenishment/presentation/replenishment_providers.dart';

class _MockRepo extends Mock implements ReplenishmentRepository {}

Replenishment _rep({
  ReplenishmentStatus status = ReplenishmentStatus.submitted,
  String? rejectionReason,
}) =>
    Replenishment(
      id: 'r1',
      companyId: 'c1',
      fundId: 'f1',
      status: status,
      requestIds: const ['req1', 'req2'],
      total: Money.fromCentavos(150000),
      reportNotes: '',
      createdByUid: 'inc',
      rejectionReason: rejectionReason,
    );

AppUser _approver() => const AppUser(
      uid: 'mgr',
      companyId: 'c1',
      role: UserRole.manager,
      displayName: 'Manager',
      email: 'm@x.io',
    );

Widget _host(ReplenishmentRepository repo, {Replenishment? rep}) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_approver())),
        replenishmentRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: ReplenishmentDetailScreen(replenishment: rep ?? _rep()),
      ),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_rep());
  });

  testWidgets('Approve opens a confirmation dialog; cancel does NOT call repo',
      (tester) async {
    final repo = _MockRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(find.text('Approve & replenish?'), findsOneWidget);
    // Amount is shown via Money.format(), not raw centavos.
    expect(find.textContaining('1,500.00'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => repo.approve(
        replenishment: any(named: 'replenishment'),
        actorUid: any(named: 'actorUid')));
  });

  testWidgets('Approve confirm calls repo.approve', (tester) async {
    final repo = _MockRepo();
    when(() => repo.approve(
            replenishment: any(named: 'replenishment'),
            actorUid: any(named: 'actorUid')))
        .thenAnswer((_) async => const Ok(null));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve & replenish'));
    // Let the repo call resolve, the success overlay run its timer, and the
    // post-decision pop complete so no pending timer leaks past the test.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    verify(() => repo.approve(
        replenishment: any(named: 'replenishment'),
        actorUid: 'mgr')).called(1);
  });

  testWidgets('Reject opens the reason sheet; cancel does NOT call repo',
      (tester) async {
    final repo = _MockRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pumpAndSettle();

    // The required-remarks sheet, not the old confirm dialog.
    expect(find.text('Reject replenishment'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Reason for rejection'),
        findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => repo.reject(
        replenishment: any(named: 'replenishment'),
        actorUid: any(named: 'actorUid'),
        reason: any(named: 'reason')));
  });

  testWidgets('Reject is blocked until a valid remark is entered',
      (tester) async {
    final repo = _MockRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pumpAndSettle();

    // The sheet's confirm button is disabled with no remark...
    final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Reject'));
    expect(confirm.onPressed, isNull);

    // ...and stays disabled for a too-short remark.
    await tester.enterText(find.byType(TextField), 'no');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Reject'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('Reject with a valid remark calls repo.reject with the reason',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.reject(
            replenishment: any(named: 'replenishment'),
            actorUid: any(named: 'actorUid'),
            reason: any(named: 'reason')))
        .thenAnswer((_) async => const Ok(null));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField), 'Amounts do not match the receipts');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    // Drain the success overlay timer + post-decision pop (see approve test).
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    verify(() => repo.reject(
        replenishment: any(named: 'replenishment'),
        actorUid: 'mgr',
        reason: 'Amounts do not match the receipts')).called(1);
  });

  testWidgets('rejected report shows the rejection-remarks callout to the reader',
      (tester) async {
    final rejected = _rep(
      status: ReplenishmentStatus.rejected,
      rejectionReason: 'Amounts do not match the receipts',
    );
    await tester.pumpWidget(_host(_MockRepo(), rep: rejected));
    await tester.pumpAndSettle();

    expect(find.text('Rejection remarks'), findsOneWidget);
    expect(find.text('Amounts do not match the receipts'), findsOneWidget);
  });

  testWidgets('rejected report with no remark hides the callout (legacy reports)',
      (tester) async {
    final rejected = _rep(status: ReplenishmentStatus.rejected);
    await tester.pumpWidget(_host(_MockRepo(), rep: rejected));
    await tester.pumpAndSettle();

    expect(find.text('Rejection remarks'), findsNothing);
  });
}
