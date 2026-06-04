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
