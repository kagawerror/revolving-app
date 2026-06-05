import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/admin_users/presentation/user_form_dialog.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/companies/domain/company.dart';

const _companies = [Company(id: 'c1', name: 'Acme')];

const _existing = AppUser(
  uid: 'u1',
  companyId: 'c1',
  companyIds: ['c1'],
  role: UserRole.incharge,
  displayName: 'Jane',
  email: 'jane@acme.com',
);

/// Pumps a button that opens the edit dialog and captures the submission.
Future<void> _pumpEdit(
  WidgetTester tester, {
  required bool showPasswordReset,
  required Future<String?> Function(UserFormSubmission) onSubmit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showUserFormDialog(
              context,
              companies: _companies,
              existing: _existing,
              showPasswordReset: showPasswordReset,
              onSubmit: onSubmit,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
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

    expect(captured, isNotNull);
    expect(captured!.newPassword, 'newpass123');
    expect(captured!.newConfirmPassword, 'newpass123');
  });
}
