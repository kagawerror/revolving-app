import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/companies/domain/company.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/companies/presentation/admin_company_context_bar.dart';
import 'package:rev_app/features/companies/presentation/admin_providers.dart';
import 'package:rev_app/features/dashboard/presentation/dashboard_providers.dart';
import 'package:rev_app/features/notifications/presentation/alerts_bell.dart';
import 'package:rev_app/features/notifications/presentation/notification_providers.dart';
import 'package:rev_app/features/replenishment/presentation/replenishment_providers.dart';
import 'package:rev_app/features/requests/presentation/aging_providers.dart';
import 'package:rev_app/features/requests/presentation/approver_inbox_providers.dart';
import 'package:rev_app/routing/role_shell_screen.dart';

const _admin = AppUser(
  uid: 'a1',
  companyId: '',
  role: UserRole.admin,
  displayName: 'Admin',
  email: 'admin@acme.test',
);

const _incharge = AppUser(
  uid: 'i1',
  companyId: 'acme',
  role: UserRole.incharge,
  displayName: 'Ina',
  email: 'ina@acme.test',
);

const _employee = AppUser(
  uid: 'e1',
  companyId: 'acme',
  role: UserRole.employee,
  displayName: 'Emma',
  email: 'emma@acme.test',
);

const _approver = AppUser(
  uid: 'm1',
  companyId: 'acme',
  role: UserRole.ceo,
  displayName: 'Cleo',
  email: 'cleo@acme.test',
);

void main() {
  /// Mounts a shell with every body-feeding provider overridden to settled,
  /// empty data so the IndexedStack mounts without a live Firestore. The bodies
  /// then render their empty states; the test asserts the shell *chrome*.
  Widget harness(AppUser user, {required UserRole role}) => ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(user)),
          // Companies / funds: empty so admin + incharge bodies show empties.
          companiesProvider
              .overrideWith((ref) => Stream.value(const <Company>[])),
          allFundsProvider.overrideWith((ref) => Stream.value(const <Fund>[])),
          companyFundsProvider.overrideWith(
              (ref, companyId) => Stream.value(const <Fund>[])),
          // Notifications drive the AlertsBell badge. Emit a settled empty list
          // (not Stream.empty, which would leave the provider perpetually
          // loading and keep a shimmer animating, hanging pumpAndSettle).
          myNotificationsProvider.overrideWith((ref) => Stream.value(const [])),
          // Approver inbox + worklist + dashboard recent activity, all settled.
          pendingRequestsProvider
              .overrideWith((ref) => Stream.value(const [])),
          acknowledgedWorklistProvider
              .overrideWith((ref) => Stream.value(const [])),
          recentRequestsProvider
              .overrideWith((ref) => Stream.value(const [])),
          pendingReplenishmentsProvider
              .overrideWith((ref) => Stream.value(const [])),
          // Approver "Approved" tab revisit lists, settled empty.
          recentApprovedRequestsProvider
              .overrideWith((ref) => Stream.value(const [])),
          recentApprovedReplenishmentsProvider
              .overrideWith((ref) => Stream.value(const [])),
          // Aging bodies: incharge flat list + admin cross-company feed, both
          // settled empty so their empty states render and pumpAndSettle ends.
          agingRequestsProvider
              .overrideWith((ref) => Stream.value(const [])),
          allOutstandingRequestsProvider
              .overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(home: RoleShellScreen(role: role)),
      );

  group('RoleShellScreen chrome', () {
    testWidgets('admin shell: 4 destinations, AlertsBell, New fund FAB, no '
        'Worklist', (tester) async {
      await tester.pumpWidget(harness(_admin, role: UserRole.admin));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.byType(AlertsBell), findsOneWidget);
      expect(find.widgetWithText(FloatingActionButton, 'New fund'),
          findsOneWidget);
      // No Worklist destination on the admin shell.
      expect(find.widgetWithText(NavigationDestination, 'Worklist'),
          findsNothing);
      // Admin shell never shows the company context bar.
      expect(find.byType(CompanyContextBar), findsNothing);
    });

    testWidgets('incharge shell: 5 destinations incl. Worklist, New request FAB',
        (tester) async {
      await tester.pumpWidget(harness(_incharge, role: UserRole.incharge));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(find.widgetWithText(NavigationDestination, 'Worklist'),
          findsOneWidget);
      expect(find.widgetWithText(FloatingActionButton, 'New request'),
          findsOneWidget);
    });

    testWidgets('employee on the incharge shell: 3 destinations, no Worklist, '
        'no Aging', (tester) async {
      await tester.pumpWidget(harness(_employee, role: UserRole.incharge));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDestination), findsNWidgets(3));
      expect(find.widgetWithText(NavigationDestination, 'Worklist'),
          findsNothing);
      // Aging is admin/incharge-only — the employee sharing the shell never
      // sees it.
      expect(find.widgetWithText(NavigationDestination, 'Aging'), findsNothing);
    });

    testWidgets('approver shell: 4 destinations (incl. Approved), no FAB',
        (tester) async {
      await tester.pumpWidget(harness(_approver, role: UserRole.ceo));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(
          find.widgetWithText(NavigationDestination, 'Approved'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('RoleShellScreen tab switching', () {
    testWidgets('incharge: Home shows context bar + FAB; Worklist keeps the bar;'
        ' Dashboard/Profile hide both', (tester) async {
      await tester.pumpWidget(harness(_incharge, role: UserRole.incharge));
      await tester.pumpAndSettle();

      // Home tab: the shell mounts the CompanyContextBar (the bar itself may
      // collapse to a SizedBox.shrink for a single-company user, but the shell
      // includes the widget) and the FAB.
      expect(find.byType(CompanyContextBar), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Worklist tab: still company-scoped, so the context bar stays; no FAB.
      await tester.tap(find.widgetWithText(NavigationDestination, 'Worklist'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanyContextBar), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);

      // Dashboard tab: not company-scoped — bar and FAB both hidden.
      await tester.tap(find.widgetWithText(NavigationDestination, 'Dashboard'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanyContextBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);

      // Profile tab: still no bar, no FAB.
      await tester.tap(find.widgetWithText(NavigationDestination, 'Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanyContextBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);

      // Back to Home: bar and FAB return.
      await tester.tap(find.widgetWithText(NavigationDestination, 'Home'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanyContextBar), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('admin: context bar absent on Home; Dashboard hides the FAB',
        (tester) async {
      await tester.pumpWidget(harness(_admin, role: UserRole.admin));
      await tester.pumpAndSettle();

      // Admin Home: FAB shown, never a context bar.
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byType(CompanyContextBar), findsNothing);

      await tester.tap(find.widgetWithText(NavigationDestination, 'Dashboard'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(CompanyContextBar), findsNothing);
    });
  });

  group('RoleShellScreen index clamp', () {
    testWidgets(
        'tab set shrinking under a stale index clamps to a valid destination',
        (tester) async {
      // Drive currentUser through a controller so we can swap the user *after*
      // the shell has settled on a now-out-of-range tab.
      final userController = StreamController<AppUser>.broadcast();
      addTearDown(userController.close);

      Widget shrinkHarness() => ProviderScope(
            overrides: [
              currentUserProvider.overrideWith((ref) => userController.stream),
              companiesProvider
                  .overrideWith((ref) => Stream.value(const <Company>[])),
              allFundsProvider
                  .overrideWith((ref) => Stream.value(const <Fund>[])),
              companyFundsProvider.overrideWith(
                  (ref, companyId) => Stream.value(const <Fund>[])),
              myNotificationsProvider
                  .overrideWith((ref) => Stream.value(const [])),
              pendingRequestsProvider
                  .overrideWith((ref) => Stream.value(const [])),
              acknowledgedWorklistProvider
                  .overrideWith((ref) => Stream.value(const [])),
              recentRequestsProvider
                  .overrideWith((ref) => Stream.value(const [])),
              pendingReplenishmentsProvider
                  .overrideWith((ref) => Stream.value(const [])),
              agingRequestsProvider
                  .overrideWith((ref) => Stream.value(const [])),
              allOutstandingRequestsProvider
                  .overrideWith((ref) => Stream.value(const [])),
            ],
            child: const MaterialApp(
                home: RoleShellScreen(role: UserRole.incharge)),
          );

      await tester.pumpWidget(shrinkHarness());
      // Start as an incharge: 5 tabs incl. Worklist (Home, Worklist, Aging,
      // Dashboard, Profile).
      userController.add(_incharge);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDestination), findsNWidgets(5));

      // Select the last tab (Profile, index 4) — only valid in the 5-tab set.
      await tester.tap(find.widgetWithText(NavigationDestination, 'Profile'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Profile'), findsOneWidget);

      // The user resolves to an employee: Worklist and Aging both drop, the set
      // shrinks to 3 (Home, Dashboard, Profile) and index 4 is now out of
      // range. The shell must clamp without throwing.
      userController.add(_employee);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationDestination), findsNWidgets(3));

      // Settled on a valid, in-range tab: the clamped index points at the last
      // surviving destination (Profile), whose title is shown in the AppBar.
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.selectedIndex, inInclusiveRange(0, 2));
      expect(nav.selectedIndex, 2);
      expect(find.widgetWithText(AppBar, 'Profile'), findsOneWidget);
    });
  });
}
