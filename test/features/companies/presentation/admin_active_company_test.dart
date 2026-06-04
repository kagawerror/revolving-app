import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/companies/presentation/admin_active_company.dart';

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

void main() {
  group('effectiveCompanyId', () {
    test('admin with no selection resolves to empty string', () {
      expect(effectiveCompanyId(_admin, null), '');
    });

    test('admin with a selection resolves to that company', () {
      expect(effectiveCompanyId(_admin, 'c1'), 'c1');
    });

    test('non-admin always resolves to its own companyId', () {
      expect(effectiveCompanyId(_incharge, null), 'c1');
      // A stray admin-active value must NOT leak into a non-admin's scope.
      expect(effectiveCompanyId(_incharge, 'c2'), 'c1');
    });
  });
}
