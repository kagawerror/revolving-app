import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/companies/domain/company.dart';
import 'package:rev_app/features/companies/domain/company_repository.dart';
import 'package:rev_app/features/companies/presentation/admin_home_screen.dart';
import 'package:rev_app/features/companies/presentation/admin_providers.dart';
import 'package:rev_app/features/messaging/presentation/messaging_providers.dart';

class _MockCompanyRepository extends Mock implements CompanyRepository {}

const _admin = AppUser(
  uid: 'a1',
  companyId: 'acme',
  role: UserRole.admin,
  displayName: 'Admin',
  email: 'admin@acme.test',
);

void main() {
  late _MockCompanyRepository repo;

  setUp(() {
    repo = _MockCompanyRepository();
  });

  Widget harness({List<Company> companies = const []}) => ProviderScope(
        overrides: [
          companyRepositoryProvider.overrideWithValue(repo),
          companiesProvider
              .overrideWith((ref) => Stream.value(companies)),
          currentUserProvider.overrideWith((ref) => Stream.value(_admin)),
          signOutProvider.overrideWithValue(() async {}),
        ],
        child: const MaterialApp(home: AdminHomeScreen()),
      );

  testWidgets('empty state shows an Add company action', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('No companies yet'), findsOneWidget);
    // Both the section header button and the empty-state action read
    // "Add company".
    expect(find.text('Add company'), findsWidgets);
  });

  testWidgets('adding a company calls create once and shows success snackbar',
      (tester) async {
    when(() => repo.create(any())).thenAnswer((_) async => const Ok('new-id'));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Open via the section-header button.
    await tester.tap(find.byIcon(Icons.add_business_rounded).first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  Globex  ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    verify(() => repo.create('Globex')).called(1);
    expect(find.byType(TextField), findsNothing); // dialog closed
    expect(find.text('Company added'), findsOneWidget);
  });

  testWidgets('on create failure the dialog stays open and no success snackbar',
      (tester) async {
    when(() => repo.create(any()))
        .thenAnswer((_) async => const Err(UnexpectedFailure('boom')));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_business_rounded).first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Globex');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    verify(() => repo.create('Globex')).called(1);
    // Dialog still open for retry.
    expect(find.byType(TextField), findsOneWidget);
    // Failure surfaced, success not.
    expect(find.text('boom'), findsOneWidget);
    expect(find.text('Company added'), findsNothing);
  });
}
