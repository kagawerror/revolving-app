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

const _ceo = AppUser(
  uid: 'ceo',
  companyId: 'c1',
  role: UserRole.ceo,
  displayName: 'Cleo',
  email: 'cleo@acme.com',
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

    // /incharge/conflicts is the incharge overdraft-resolution queue — it moves
    // money, so it is view-restricted to incharge + admin exactly like
    // /incharge/acknowledged.
    test('incharge may reach the /incharge/conflicts queue', () {
      expect(
        redirectFor(
            auth: const AsyncData(_incharge),
            location: '/incharge/conflicts'),
        isNull,
      );
    });

    test('admin superuser may reach the /incharge/conflicts queue', () {
      expect(
        redirectFor(
            auth: const AsyncData(_admin), location: '/incharge/conflicts'),
        isNull,
      );
    });

    test('approver is bounced away from /incharge/conflicts to /approvals', () {
      expect(
        redirectFor(
            auth: const AsyncData(_approver),
            location: '/incharge/conflicts'),
        '/approvals',
      );
    });

    test('employee is bounced away from /incharge/conflicts to its home', () {
      // Employee shares the /incharge shell; the targeted rule must bounce it.
      expect(
        redirectFor(
            auth: const AsyncData(_employee),
            location: '/incharge/conflicts'),
        homeFor(UserRole.employee),
      );
    });

    // /approvals/review is the approver post-release review queue. It lives
    // under the /approvals subtree, so the role-home prefix guard keeps
    // non-approvers out; admin passes via the superuser bypass.
    test('approver may reach the /approvals/review queue', () {
      expect(
        redirectFor(
            auth: const AsyncData(_approver), location: '/approvals/review'),
        isNull,
      );
    });

    test('admin superuser may reach the /approvals/review queue', () {
      expect(
        redirectFor(
            auth: const AsyncData(_admin), location: '/approvals/review'),
        isNull,
      );
    });

    test('incharge is bounced away from /approvals/review to /incharge', () {
      expect(
        redirectFor(
            auth: const AsyncData(_incharge), location: '/approvals/review'),
        '/incharge',
      );
    });

    test('employee is bounced away from /approvals/review to its home', () {
      expect(
        redirectFor(
            auth: const AsyncData(_employee), location: '/approvals/review'),
        homeFor(UserRole.employee),
      );
    });

    // /approvals/adjust-fund is the Fund Adjustment entry, gated to
    // canAdjustFund (admin || ceo). It lives under the /approvals subtree, so a
    // CEO (an approver) passes via the role-home prefix guard and admin passes
    // via the superuser bypass. Other roles are bounced.
    test('ceo may reach /approvals/adjust-fund', () {
      expect(
        redirectFor(
            auth: const AsyncData(_ceo), location: '/approvals/adjust-fund'),
        isNull,
      );
    });

    test('admin superuser may reach /approvals/adjust-fund', () {
      expect(
        redirectFor(
            auth: const AsyncData(_admin), location: '/approvals/adjust-fund'),
        isNull,
      );
    });

    test('incharge is bounced away from /approvals/adjust-fund to /incharge', () {
      expect(
        redirectFor(
            auth: const AsyncData(_incharge),
            location: '/approvals/adjust-fund'),
        '/incharge',
      );
    });

    test('employee is bounced away from /approvals/adjust-fund to its home', () {
      expect(
        redirectFor(
            auth: const AsyncData(_employee),
            location: '/approvals/adjust-fund'),
        homeFor(UserRole.employee),
      );
    });

    test('non-adjuster approver (manager) reaches /approvals/adjust-fund route',
        () {
      // NOTE: the redirect is role-SHELL based, not canAdjustFund-based. A
      // manager (approver, !canAdjustFund) is NOT bounced by the router because
      // the route is under the /approvals subtree it owns. The screen itself
      // fail-safes on canAdjustFund (see AdjustFundScreen._AdjustFundBody) and
      // the CEO/admin AppBar entry is the only navigation into it. This is the
      // manual-verification gap: router-level gating is by shell, action-level
      // gating is by canAdjustFund.
      expect(
        redirectFor(
            auth: const AsyncData(_approver),
            location: '/approvals/adjust-fund'),
        isNull,
      );
    });
  });
}
