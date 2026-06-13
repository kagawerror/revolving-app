import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/companies/domain/company.dart';
import 'package:rev_app/features/companies/presentation/switchable_companies.dart';
import 'package:rev_app/features/reports/presentation/report_screen.dart';

AppUser _user(UserRole role) => AppUser(
      uid: 'u1',
      companyId: 'c1',
      companyIds: const ['c1'],
      role: role,
      displayName: 'Test',
      email: 't@e.com',
    );

/// An admin has no home company of their own; their scope comes from the
/// in-session company picker (empty until they choose one).
AppUser _admin() => const AppUser(
      uid: 'admin1',
      companyId: '',
      companyIds: [],
      role: UserRole.admin,
      displayName: 'Admin',
      email: 'a@e.com',
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

  testWidgets(
      'an admin with no company selected sees the select-company prompt, '
      'not the tabs or a misleading empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_admin())),
          // Two companies to choose from; none selected (adminActiveCompany
          // defaults to null) so the scope resolves to '' and the report
          // providers short-circuit without touching Firestore.
          switchableCompaniesProvider.overrideWithValue(
            const AsyncData<List<Company>>([
              Company(id: 'c1', name: 'Acme'),
              Company(id: 'c2', name: 'Beta'),
            ]),
          ),
        ],
        child: const MaterialApp(home: ReportScreen()),
      ),
    );
    await tester.pump(); // let the auth stream emit

    // The "select a company" prompt is shown instead of an empty report.
    expect(find.text('Select a company'), findsWidgets);
    // The report tabs are hidden until a company is chosen.
    expect(find.text('Released'), findsNothing);
    expect(find.text('Replenishments'), findsNothing);
  });
}
