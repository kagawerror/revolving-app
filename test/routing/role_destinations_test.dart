import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/routing/role_destinations.dart';

void main() {
  group('destinationsForRole', () {
    test('admin => Home, Aging, Dashboard, Profile (no acknowledged)', () {
      final dests = destinationsForRole(UserRole.admin, showAcknowledged: false);

      expect(dests.map((d) => d.tab).toList(), [
        ShellTab.home,
        ShellTab.aging,
        ShellTab.dashboard,
        ShellTab.profile,
      ]);
      expect(dests.any((d) => d.tab == ShellTab.acknowledged), isFalse);

      // Titles / labels are correct on the admin home.
      final home = dests.first;
      expect(home.title, 'Admin');
      expect(home.label, 'Home');
      final aging = dests.firstWhere((d) => d.tab == ShellTab.aging);
      expect(aging.title, 'Aging');
      expect(aging.label, 'Aging');
    });

    test('admin: exactly the Home destination carries a FAB', () {
      final dests = destinationsForRole(UserRole.admin, showAcknowledged: false);
      final withFab = dests.where((d) => d.fab != null).toList();

      expect(withFab, hasLength(1));
      expect(withFab.single.tab, ShellTab.home);
      expect(withFab.single.fab!.label, 'New fund');
      expect(withFab.single.fab!.pushRoute, '/admin/create-fund');
    });

    test('incharge with showAcknowledged:true + showAging:true => Home, '
        'Worklist, Aging, Dashboard, Profile', () {
      final dests = destinationsForRole(
        UserRole.incharge,
        showAcknowledged: true,
        showAging: true,
      );

      expect(dests.map((d) => d.tab).toList(), [
        ShellTab.home,
        ShellTab.acknowledged,
        ShellTab.aging,
        ShellTab.dashboard,
        ShellTab.profile,
      ]);
      // Worklist tab uses the shortened label but the full title.
      final ack = dests.firstWhere((d) => d.tab == ShellTab.acknowledged);
      expect(ack.label, 'Worklist');
      expect(ack.title, 'Acknowledged');
    });

    test('incharge: exactly the Home destination carries a FAB', () {
      final dests = destinationsForRole(
        UserRole.incharge,
        showAcknowledged: true,
        showAging: true,
      );
      final withFab = dests.where((d) => d.fab != null).toList();

      expect(withFab, hasLength(1));
      expect(withFab.single.tab, ShellTab.home);
      expect(withFab.single.fab!.label, 'New request');
      expect(withFab.single.fab!.pushRoute, '/incharge/create');
    });

    test('incharge with showAcknowledged:false, showAging:true => Aging but no '
        'Worklist', () {
      final dests = destinationsForRole(
        UserRole.incharge,
        showAcknowledged: false,
        showAging: true,
      );

      expect(dests.map((d) => d.tab).toList(), [
        ShellTab.home,
        ShellTab.aging,
        ShellTab.dashboard,
        ShellTab.profile,
      ]);
      expect(dests.any((d) => d.tab == ShellTab.acknowledged), isFalse);
    });

    test('employee shares the incharge shell: showAcknowledged:false, '
        'showAging:false => Home, Dashboard, Profile (no Worklist, no Aging)',
        () {
      final dests = destinationsForRole(
        UserRole.employee,
        showAcknowledged: false,
        showAging: false,
      );

      expect(dests.map((d) => d.tab).toList(), [
        ShellTab.home,
        ShellTab.dashboard,
        ShellTab.profile,
      ]);
      expect(dests.any((d) => d.tab == ShellTab.acknowledged), isFalse);
      // The Aging tab is admin/incharge-only — the employee never gets it.
      expect(dests.any((d) => d.tab == ShellTab.aging), isFalse);
    });

    test('approver => Home, Dashboard, Profile with NO Home FAB', () {
      for (final role in [UserRole.superior, UserRole.manager, UserRole.ceo]) {
        final dests = destinationsForRole(role, showAcknowledged: false);

        expect(dests.map((d) => d.tab).toList(),
            [ShellTab.home, ShellTab.dashboard, ShellTab.profile],
            reason: '$role tab set');
        expect(dests.first.title, 'Approvals', reason: '$role home title');
        // Approvers don't create funds/requests — zero FABs anywhere.
        expect(dests.where((d) => d.fab != null), isEmpty,
            reason: '$role has no FAB');
      }
    });
  });
}
