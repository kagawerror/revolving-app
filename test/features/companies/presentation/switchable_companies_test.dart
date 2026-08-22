import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/companies/domain/company.dart';
import 'package:rev_app/features/companies/presentation/switchable_companies.dart';

const _all = [
  Company(id: 'c1', name: 'Acme'),
  Company(id: 'c2', name: 'Globex'),
  Company(id: 'c3', name: 'Initech'),
];

const _admin = AppUser(
  uid: 'a',
  companyId: '',
  role: UserRole.admin,
  displayName: 'Admin',
  email: 'admin@x.com',
);

const _multi = AppUser(
  uid: 'm',
  companyId: 'c1',
  role: UserRole.incharge,
  displayName: 'Mia',
  email: 'mia@x.com',
  companyIds: ['c1', 'c3'],
);

const _legacy = AppUser(
  uid: 'l',
  companyId: 'c2',
  role: UserRole.manager,
  displayName: 'Leo',
  email: 'leo@x.com',
);

void main() {
  group('companiesForUser', () {
    test('admin gets every company', () {
      expect(companiesForUser(_admin, _all), _all);
    });

    test('non-admin gets only their membership companies', () {
      expect(
        companiesForUser(_multi, _all).map((c) => c.id),
        ['c1', 'c3'],
      );
    });

    test('legacy non-admin gets only its primary company', () {
      expect(
        companiesForUser(_legacy, _all).map((c) => c.id),
        ['c2'],
      );
    });
  });
}
