import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/company.dart';
import 'admin_providers.dart';

/// The companies [user] may switch between, given the full company set [all]:
///   * **admin** => every company (superuser).
///   * **non-admin** => only their [AppUser.companyMemberships], intersected
///     with the companies that actually exist (legacy users resolve to just
///     their primary company via `companyMemberships`).
///
/// Pure + top-level: the unit-testable seam behind [switchableCompaniesProvider].
List<Company> companiesForUser(AppUser user, List<Company> all) {
  if (user.role.isAdmin) return all;
  final memberships = user.companyMemberships.toSet();
  return all.where((c) => memberships.contains(c.id)).toList();
}

/// Canonical source of truth for the companies the current user can switch
/// between in [CompanyContextBar]. Watches the auth + companies streams and
/// applies [companiesForUser]. Null-safe while auth is loading (returns
/// `const []` until a user resolves), so the bar never throws on cold start.
final switchableCompaniesProvider = Provider<AsyncValue<List<Company>>>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  final companiesAsync = ref.watch(companiesProvider);
  if (me == null) return const AsyncValue.data(<Company>[]);
  return companiesAsync.whenData((all) => companiesForUser(me, all));
});
