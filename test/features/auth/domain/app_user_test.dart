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
