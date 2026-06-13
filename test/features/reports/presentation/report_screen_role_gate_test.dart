import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/reports/presentation/report_screen.dart';

AppUser _user(UserRole role) => AppUser(
      uid: 'u1',
      companyId: 'c1',
      companyIds: const ['c1'],
      role: role,
      displayName: 'Test',
      email: 't@e.com',
    );

Widget _screenAs(UserRole role) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user(role))),
      ],
      child: const MaterialApp(home: ReportScreen()),
    );

void main() {
  testWidgets(
      'a manager (canViewReports == false) sees the not-authorized fallback',
      (tester) async {
    // Sanity: the precondition the gate relies on.
    expect(UserRole.manager.canViewReports, isFalse);

    await tester.pumpWidget(_screenAs(UserRole.manager));
    await tester.pump(); // let the auth stream emit

    // The not-authorized fallback is shown; the report tabs are not.
    expect(find.text('Not available for your role'), findsOneWidget);
    expect(find.text('Released'), findsNothing);
    expect(find.text('Replenishments'), findsNothing);
  });

  testWidgets('a superior (canViewReports == false) is also gated out',
      (tester) async {
    expect(UserRole.superior.canViewReports, isFalse);

    await tester.pumpWidget(_screenAs(UserRole.superior));
    await tester.pump();

    expect(find.text('Not available for your role'), findsOneWidget);
  });
}
