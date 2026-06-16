import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/core/widgets/skeleton.dart';
import 'package:rev_app/features/admin_users/presentation/user_form_dialog.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/companies/domain/company.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/companies/presentation/admin_providers.dart';

const _companies = [
  Company(id: 'c1', name: 'Acme'),
  Company(id: 'c2', name: 'Globex'),
];

final _funds = [
  Fund(
    id: 'f1',
    companyId: 'c1',
    name: 'Petty cash',
    originalBudget: Money.fromCentavos(500000),
    availableBalance: Money.fromCentavos(420000),
    lowBalanceThresholdPct: 3,
    status: FundStatus.active,
  ),
];

const _existing = AppUser(
  uid: 'u1',
  companyId: 'c1',
  companyIds: ['c1'],
  role: UserRole.incharge,
  displayName: 'Jane',
  email: 'jane@acme.com',
);

/// Pumps a button that opens the edit dialog and captures the submission.
///
/// The dialog watches [allFundsProvider] directly (FIX 1), so funds are wired
/// through a ProviderScope override rather than a frozen prop. Pass
/// [fundsLoading] to keep the stream pending (drives the picker skeleton).
Future<void> _pumpEdit(
  WidgetTester tester, {
  required bool showPasswordReset,
  required Future<String?> Function(UserFormSubmission) onSubmit,
  List<Fund> funds = const [],
  bool fundsLoading = false,
  AppUser? existing = _existing,
  // When the funds stream stays pending the shimmer skeleton animates forever,
  // so pumpAndSettle would time out. Loading tests pass false and pump a few
  // fixed frames instead.
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        allFundsProvider.overrideWith(
          // A never-emitting stream keeps the provider in AsyncLoading; a
          // value stream resolves to the funds. Drives the picker skeleton vs
          // chips without faking AsyncValue directly.
          (ref) =>
              fundsLoading ? const Stream<List<Fund>>.empty() : Stream.value(funds),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showUserFormDialog(
                context,
                companies: _companies,
                existing: existing,
                showPasswordReset: showPasswordReset,
                onSubmit: onSubmit,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Open + let the route transition run without waiting on the shimmer.
    await tester.pump(); // schedule the dialog route
    await tester.pump(const Duration(milliseconds: 350));
  }
}

void main() {
  testWidgets('hides the reset field when showPasswordReset is false',
      (tester) async {
    await _pumpEdit(
      tester,
      showPasswordReset: false,
      onSubmit: (_) async => null,
    );
    expect(find.text('New password (optional)'), findsNothing);
  });

  testWidgets('shows the reset field on edit when showPasswordReset is true',
      (tester) async {
    await _pumpEdit(
      tester,
      showPasswordReset: true,
      onSubmit: (_) async => null,
    );
    expect(find.text('New password (optional)'), findsOneWidget);
    expect(
      find.text('Leave blank to keep the current password.'),
      findsOneWidget,
    );
  });

  testWidgets('blank reset fields still allow save (newPassword empty)',
      (tester) async {
    UserFormSubmission? captured;
    await _pumpEdit(
      tester,
      showPasswordReset: true,
      onSubmit: (s) async {
        captured = s;
        return null; // success closes the dialog
      },
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // _existing is an incharge with no funds → the zero-fund warning confirm
    // intervenes before submit; proceed through it.
    await tester.tap(find.text('Save anyway'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.newPassword, isEmpty);
    expect(captured!.newConfirmPassword, isEmpty);
    // Dialog closed on success.
    expect(find.text('New password (optional)'), findsNothing);
  });

  testWidgets('a too-short reset password blocks save inline', (tester) async {
    var submitCalled = false;
    await _pumpEdit(
      tester,
      showPasswordReset: true,
      onSubmit: (_) async {
        submitCalled = true;
        return null;
      },
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New password (optional)'),
      'ab',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Field validator rejected it, so onSubmit never ran and the dialog stays.
    expect(submitCalled, isFalse);
    expect(find.text('New password (optional)'), findsOneWidget);
  });

  testWidgets('a filled, valid, matching reset password reaches onSubmit',
      (tester) async {
    UserFormSubmission? captured;
    await _pumpEdit(
      tester,
      showPasswordReset: true,
      onSubmit: (s) async {
        captured = s;
        return null;
      },
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New password (optional)'),
      'newpass123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm new password'),
      'newpass123',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // Incharge zero-fund warning confirm → proceed.
    await tester.tap(find.text('Save anyway'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.newPassword, 'newpass123');
    expect(captured!.newConfirmPassword, 'newpass123');
  });

  group('fund assignment', () {
    testWidgets('the fund picker shows for an incharge', (tester) async {
      await _pumpEdit(
        tester,
        showPasswordReset: false,
        funds: _funds,
        onSubmit: (_) async => null,
      );
      expect(find.text('Assigned funds'), findsOneWidget);
      expect(find.text('Petty cash'), findsOneWidget);
      // Fund balance label uses Money.format().
      expect(
        find.text(Money.fromCentavos(420000).format()),
        findsOneWidget,
      );
    });

    testWidgets('the fund picker is hidden for a non-incharge role',
        (tester) async {
      await _pumpEdit(
        tester,
        showPasswordReset: false,
        funds: _funds,
        onSubmit: (_) async => null,
      );
      // Switch role to manager.
      await tester.tap(find.byType(DropdownButtonFormField<UserRole>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manager').last);
      await tester.pumpAndSettle();
      expect(find.text('Assigned funds'), findsNothing);
    });

    testWidgets(
        'selecting a fund and confirming reaches onSubmit with the fund id',
        (tester) async {
      UserFormSubmission? captured;
      await _pumpEdit(
        tester,
        showPasswordReset: false,
        funds: _funds,
        onSubmit: (s) async {
          captured = s;
          return null;
        },
      );
      await tester.ensureVisible(find.text('Petty cash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Petty cash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // A fund is now assigned → the NEUTRAL confirm (not the zero-fund warning).
      expect(find.text('Confirm fund assignment'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.fundIds, ['f1']);
    });

    testWidgets('cancelling the confirm does not submit', (tester) async {
      var submitted = false;
      await _pumpEdit(
        tester,
        showPasswordReset: false,
        funds: _funds,
        onSubmit: (_) async {
          submitted = true;
          return null;
        },
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // Existing incharge with zero funds → warning confirm.
      expect(find.text('Save with no funds?'), findsOneWidget);
      // Two 'Cancel' buttons are in the tree (form + confirm); tap the confirm's.
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(submitted, isFalse);
      // The form dialog is still open.
      expect(find.text('Edit user'), findsOneWidget);
    });

    testWidgets(
        'deselecting a company prunes its funds from the submission',
        (tester) async {
      // Incharge in BOTH companies with fund f1 (owned by c1) pre-assigned, so
      // a fund chip starts selected. c2 stays selected after we drop c1, so the
      // picker survives and save can proceed (proving the prune, not just an
      // empty-membership block).
      const existing = AppUser(
        uid: 'u2',
        companyId: 'c1',
        companyIds: ['c1', 'c2'],
        role: UserRole.incharge,
        displayName: 'Multi',
        email: 'multi@acme.com',
        assignedFundIds: ['f1'],
      );
      UserFormSubmission? captured;
      await _pumpEdit(
        tester,
        showPasswordReset: false,
        funds: _funds,
        existing: existing,
        onSubmit: (s) async {
          captured = s;
          return null;
        },
      );
      // f1 starts assigned (1 selected) and its chip is visible.
      expect(find.text('Petty cash'), findsOneWidget);

      // Deselect company A (Acme / c1) — this should prune fund f1.
      final acmeChip = find.widgetWithText(FilterChip, 'Acme');
      await tester.ensureVisible(acmeChip);
      await tester.pumpAndSettle();
      await tester.tap(acmeChip);
      await tester.pumpAndSettle();

      // The c1 fund chip is gone (its company group dropped) and only c2 remains.
      expect(find.text('Petty cash'), findsNothing);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // Pruned to zero funds → existing-incharge zero-fund warning; proceed.
      expect(find.text('Save with no funds?'), findsOneWidget);
      await tester.tap(find.text('Save anyway'));
      await tester.pumpAndSettle();

      // The orphaned fund did NOT survive into the submission.
      expect(captured, isNotNull);
      expect(captured!.fundIds, isEmpty);
      expect(captured!.companyIds, ['c2']);
    });

    testWidgets('shows the loading skeleton and no fund chips while loading',
        (tester) async {
      await _pumpEdit(
        tester,
        showPasswordReset: false,
        funds: _funds,
        fundsLoading: true,
        settle: false,
        onSubmit: (_) async => null,
      );
      // The picker header is present (incharge role) but the funds haven't
      // resolved: skeleton instead of chips, and no fund name leaks through.
      // (Company FilterChips still render — only the fund chips are gated.)
      expect(find.text('Assigned funds'), findsOneWidget);
      expect(find.byType(SkeletonList), findsWidgets);
      expect(find.text('Petty cash'), findsNothing);
    });
  });
}
