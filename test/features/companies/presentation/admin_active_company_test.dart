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

const _multi = AppUser(
  uid: 'm',
  companyId: 'c1',
  role: UserRole.incharge,
  displayName: 'Mia',
  email: 'mia@acme.com',
  companyIds: ['c1', 'c2', 'c3'],
);

void main() {
  group('effectiveCompanyId', () {
    test('admin with no selection resolves to empty string', () {
      expect(effectiveCompanyId(_admin, null), '');
    });

    test('admin with a selection resolves to that company', () {
      expect(effectiveCompanyId(_admin, 'c1'), 'c1');
    });

    test('single-membership non-admin ignores any session selection', () {
      expect(effectiveCompanyId(_incharge, null), 'c1');
      // A stray admin-active value must NOT leak into a single-company scope.
      expect(effectiveCompanyId(_incharge, 'c2'), 'c1');
    });

    test('multi-membership honors a valid session selection', () {
      expect(effectiveCompanyId(_multi, 'c2'), 'c2');
      expect(effectiveCompanyId(_multi, 'c3'), 'c3');
    });

    test('multi-membership falls back to first membership on null selection', () {
      expect(effectiveCompanyId(_multi, null), 'c1');
    });

    test('multi-membership falls back to first membership on a stray selection', () {
      // 'c9' isn't in the membership — must not leak; resolve to first member.
      expect(effectiveCompanyId(_multi, 'c9'), 'c1');
    });

    test('multi-membership with a stray primary resolves to first membership', () {
      // Malformed doc: primary companyId ('cX') is NOT in companyIds. The
      // fallback must stay inside the membership list the UI shows, so it
      // resolves to memberships.first ('c1'), never the stray primary.
      const strayPrimary = AppUser(
        uid: 'm2',
        companyId: 'cX',
        role: UserRole.incharge,
        displayName: 'Mona',
        email: 'mona@acme.com',
        companyIds: ['c1', 'c2', 'c3'],
      );
      expect(effectiveCompanyId(strayPrimary, null), 'c1');
      expect(effectiveCompanyId(strayPrimary, 'c9'), 'c1');
    });
  });
}
