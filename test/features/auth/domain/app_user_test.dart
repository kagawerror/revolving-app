import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';

void main() {
  test('UserRole parses from string and defaults to employee', () {
    expect(UserRole.fromName('incharge'), UserRole.incharge);
    expect(UserRole.fromName('garbage'), UserRole.employee);
  });

  test('approver roles can acknowledge requests', () {
    expect(UserRole.manager.canApprove, isTrue);
    expect(UserRole.ceo.canApprove, isTrue);
    expect(UserRole.superior.canApprove, isTrue);
    expect(UserRole.incharge.canApprove, isFalse);
    expect(UserRole.employee.canApprove, isFalse);
  });

  test('only incharge can release and manage fund', () {
    expect(UserRole.incharge.canManageFund, isTrue);
    expect(UserRole.manager.canManageFund, isFalse);
  });

  test('only admin and ceo may adjust a fund balance', () {
    expect(UserRole.admin.canAdjustFund, isTrue);
    expect(UserRole.ceo.canAdjustFund, isTrue);
    expect(UserRole.manager.canAdjustFund, isFalse);
    expect(UserRole.superior.canAdjustFund, isFalse);
    expect(UserRole.incharge.canAdjustFund, isFalse);
    expect(UserRole.employee.canAdjustFund, isFalse);
  });

  group('superuser-or-admin capability getters', () {
    test('admin satisfies both *OrAdmin getters', () {
      expect(UserRole.admin.canApproveOrAdmin, isTrue);
      expect(UserRole.admin.canManageFundOrAdmin, isTrue);
    });

    test('canApproveOrAdmin tracks canApprove for non-admin roles', () {
      for (final role in UserRole.values) {
        if (role == UserRole.admin) continue;
        expect(role.canApproveOrAdmin, role.canApprove,
            reason: '$role canApproveOrAdmin should match canApprove');
      }
    });

    test('canManageFundOrAdmin tracks canManageFund for non-admin roles', () {
      for (final role in UserRole.values) {
        if (role == UserRole.admin) continue;
        expect(role.canManageFundOrAdmin, role.canManageFund,
            reason: '$role canManageFundOrAdmin should match canManageFund');
      }
    });

    test('role-pure getters are unchanged for every role (regression lock)', () {
      const expected = {
        UserRole.admin: (canApprove: false, canManageFund: false, isAdmin: true),
        UserRole.ceo: (canApprove: true, canManageFund: false, isAdmin: false),
        UserRole.manager:
            (canApprove: true, canManageFund: false, isAdmin: false),
        UserRole.superior:
            (canApprove: true, canManageFund: false, isAdmin: false),
        UserRole.incharge:
            (canApprove: false, canManageFund: true, isAdmin: false),
        UserRole.employee:
            (canApprove: false, canManageFund: false, isAdmin: false),
      };
      for (final role in UserRole.values) {
        final e = expected[role]!;
        expect(role.canApprove, e.canApprove, reason: '$role.canApprove');
        expect(role.canManageFund, e.canManageFund,
            reason: '$role.canManageFund');
        expect(role.isAdmin, e.isAdmin, reason: '$role.isAdmin');
      }
    });
  });

  group('companyMemberships', () {
    test('admin has no memberships regardless of companyIds', () {
      const admin = AppUser(
        uid: 'a',
        companyId: '',
        role: UserRole.admin,
        displayName: 'Admin',
        email: 'admin@x.com',
        companyIds: ['c1', 'c2'],
      );
      expect(admin.companyMemberships, const <String>[]);
    });

    test('non-admin with companyIds returns the list', () {
      const u = AppUser(
        uid: 'u',
        companyId: 'c1',
        role: UserRole.incharge,
        displayName: 'I',
        email: 'i@x.com',
        companyIds: ['c1', 'c2'],
      );
      expect(u.companyMemberships, ['c1', 'c2']);
    });

    test('non-admin legacy (empty companyIds) falls back to [companyId]', () {
      const u = AppUser(
        uid: 'u',
        companyId: 'c1',
        role: UserRole.incharge,
        displayName: 'I',
        email: 'i@x.com',
      );
      expect(u.companyMemberships, ['c1']);
    });
  });

  test('fromMap builds an AppUser', () {
    final u = AppUser.fromMap('uid1', {
      'companyId': 'c1',
      'role': 'incharge',
      'displayName': 'Ana',
      'email': 'ana@x.com',
    });
    expect(u.uid, 'uid1');
    expect(u.companyId, 'c1');
    expect(u.role, UserRole.incharge);
  });

  group('AppUser serialization', () {
    test('fromMap reads new fields', () {
      final u = AppUser.fromMap('u1', {
        'companyId': 'c1',
        'role': 'incharge',
        'displayName': 'Ana',
        'email': 'ana@x.com',
        'photoUrl': 'https://cdn/x.jpg',
        'themeMode': 'dark',
        'accentId': 'indigo',
      });
      expect(u.photoUrl, 'https://cdn/x.jpg');
      expect(u.themeMode, ThemeMode.dark);
      expect(u.accentId, 'indigo');
    });
    test('fromMap applies defaults for legacy docs missing new fields', () {
      final u = AppUser.fromMap('u1', {
        'companyId': 'c1',
        'role': 'incharge',
        'displayName': 'Ana',
        'email': 'ana@x.com',
      });
      expect(u.photoUrl, isNull);
      expect(u.themeMode, ThemeMode.system);
      expect(u.accentId, 'forest');
    });
    test('fromMap reads companyIds and defaults to empty for legacy docs', () {
      final withIds = AppUser.fromMap('u1', {
        'companyId': 'c1',
        'role': 'incharge',
        'displayName': 'Ana',
        'email': 'ana@x.com',
        'companyIds': ['c1', 'c2'],
      });
      expect(withIds.companyIds, ['c1', 'c2']);
      final legacy = AppUser.fromMap('u1', {
        'companyId': 'c1',
        'role': 'incharge',
        'displayName': 'Ana',
        'email': 'ana@x.com',
      });
      expect(legacy.companyIds, const <String>[]);
    });

    test('toMap includes companyIds', () {
      const u = AppUser(
        uid: 'u1',
        companyId: 'c1',
        role: UserRole.incharge,
        displayName: 'Ana',
        email: 'ana@x.com',
        companyIds: ['c1', 'c2'],
      );
      expect(u.toMap()['companyIds'], ['c1', 'c2']);
    });

    test('fromMap reads mustChangePassword; absent defaults to false', () {
      final forced = AppUser.fromMap('u1', {
        'companyId': 'c1',
        'role': 'incharge',
        'displayName': 'Ana',
        'email': 'ana@x.com',
        'mustChangePassword': true,
      });
      expect(forced.mustChangePassword, isTrue);
      final legacy = AppUser.fromMap('u1', {
        'companyId': 'c1',
        'role': 'incharge',
        'displayName': 'Ana',
        'email': 'ana@x.com',
      });
      expect(legacy.mustChangePassword, isFalse);
    });

    test('toMap includes mustChangePassword', () {
      const u = AppUser(
        uid: 'u1',
        companyId: 'c1',
        role: UserRole.incharge,
        displayName: 'Ana',
        email: 'ana@x.com',
        mustChangePassword: true,
      );
      expect(u.toMap()['mustChangePassword'], true);
    });

    test('toMap round-trips themeMode as a string', () {
      final u = AppUser.fromMap('u1', {
        'companyId': 'c1',
        'role': 'ceo',
        'displayName': 'B',
        'email': 'b@x.com',
        'themeMode': 'light',
        'accentId': 'rose',
      });
      final map = u.toMap();
      expect(map['themeMode'], 'light');
      expect(map['accentId'], 'rose');
    });
  });
}
