import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/routing/app_router.dart';

const _admin = AppUser(
  uid: 'a',
  companyId: '',
  role: UserRole.admin,
  displayName: 'Admin',
  email: 'admin@acme.com',
);

const _incharge = AppUser(
  uid: 'i',
  companyId: 'c1',
  role: UserRole.incharge,
  displayName: 'Ina',
  email: 'ina@acme.com',
);

const _approver = AppUser(
  uid: 'm',
  companyId: 'c1',
  role: UserRole.manager,
  displayName: 'Manny',
  email: 'manny@acme.com',
);

const _employee = AppUser(
  uid: 'e',
  companyId: 'c1',
  role: UserRole.employee,
  displayName: 'Emma',
  email: 'emma@acme.com',
);

void main() {
  test('homeFor routes each role to its shell', () {
    expect(homeFor(UserRole.admin), '/admin');
    expect(homeFor(UserRole.incharge), '/incharge');
    expect(homeFor(UserRole.manager), '/approvals');
    expect(homeFor(UserRole.ceo), '/approvals');
    expect(homeFor(UserRole.superior), '/approvals');
    expect(homeFor(UserRole.employee), '/incharge');
  });

  group('redirectFor', () {
    test('stays null while auth is loading (no flicker)', () {
      expect(
        redirectFor(auth: const AsyncLoading(), location: '/admin'),
        isNull,
      );
    });

    test('unauthenticated caller stays on /setup', () {
      expect(
        redirectFor(auth: const AsyncData(null), location: '/setup'),
        isNull,
      );
    });

    test('unauthenticated caller stays on /login', () {
      expect(
        redirectFor(auth: const AsyncData(null), location: '/login'),
        isNull,
      );
    });

    test('unauthenticated caller on a protected route goes to /login', () {
      expect(
        redirectFor(auth: const AsyncData(null), location: '/admin'),
        '/login',
      );
    });

    test('authenticated admin is redirected from /setup to /admin', () {
      expect(
        redirectFor(auth: const AsyncData(_admin), location: '/setup'),
        '/admin',
      );
    });

    test('authenticated admin is redirected from /login to /admin', () {
      expect(
        redirectFor(auth: const AsyncData(_admin), location: '/login'),
        '/admin',
      );
    });

    test('authenticated admin already on /admin stays put', () {
      expect(
        redirectFor(auth: const AsyncData(_admin), location: '/admin'),
        isNull,
      );
    });

    test('authenticated admin can reach the shared /profile route', () {
      // /profile is role-agnostic: it must NOT be bounced back to the role home.
      expect(
        redirectFor(auth: const AsyncData(_admin), location: '/profile'),
        isNull,
      );
    });

    test('admin superuser may visit any other role shell (no redirect)', () {
      // Admin is a superuser: it operates the incharge + approval workflows in
      // any company, so the role-home guard must NOT bounce it back to /admin.
      expect(
        redirectFor(auth: const AsyncData(_admin), location: '/incharge'),
        isNull,
      );
      expect(
        redirectFor(auth: const AsyncData(_admin), location: '/approvals'),
        isNull,
      );
    });

    test('non-admin incharge on /approvals is still bounced to /incharge', () {
      // Escalation guard intact: only admin gets the cross-shell pass.
      expect(
        redirectFor(auth: const AsyncData(_incharge), location: '/approvals'),
        '/incharge',
      );
    });

    test('non-admin incharge stays on its own /incharge shell', () {
      expect(
        redirectFor(auth: const AsyncData(_incharge), location: '/incharge'),
        isNull,
      );
    });

    // /incharge/acknowledged is view-restricted: ONLY incharge + admin may see
    // it. Approvers are already bounced by the prefix guard; an employee shares
    // the /incharge shell yet must still be bounced by the targeted sub-path
    // rule, since its home (/incharge) would otherwise admit it by prefix.
    test('incharge may reach /incharge/acknowledged worklist', () {
      expect(
        redirectFor(
            auth: const AsyncData(_incharge),
            location: '/incharge/acknowledged'),
        isNull,
      );
    });

    test('admin superuser may reach /incharge/acknowledged worklist', () {
      expect(
        redirectFor(
            auth: const AsyncData(_admin), location: '/incharge/acknowledged'),
        isNull,
      );
    });

    test('approver is bounced away from /incharge/acknowledged to /approvals', () {
      expect(
        redirectFor(
            auth: const AsyncData(_approver),
            location: '/incharge/acknowledged'),
        '/approvals',
      );
    });

    test('employee is bounced away from /incharge/acknowledged to its home', () {
      // Employee shares the /incharge shell (homeFor(employee) == /incharge), so
      // the plain prefix guard would admit it. The targeted view-permission rule
      // must bounce it back to its home instead.
      expect(
        redirectFor(
            auth: const AsyncData(_employee),
            location: '/incharge/acknowledged'),
        homeFor(UserRole.employee),
      );
    });
  });
}
