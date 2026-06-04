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
  });
}
