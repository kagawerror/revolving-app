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
}
