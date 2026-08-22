import '../../auth/domain/app_user.dart';

/// Resolves the company a [user] is operating in.
///
///   * **admin** — a superuser with an empty `companyId`; scope is the
///     in-session [sessionActive] selection (behind `adminActiveCompanyProvider`),
///     or `''` (callers no-op their company-scoped streams) until one is picked.
///   * **single-company non-admin** — pinned to their one membership; a stray
///     session value never leaks into their scope.
///   * **multi-company non-admin** — honors [sessionActive] when it's a real
///     membership; otherwise (null or stray) defaults to the first membership.
///
/// Pure + top-level on purpose: it's the unit-testable seam for company scoping
/// without dragging in widgets or Riverpod.
String effectiveCompanyId(AppUser user, String? sessionActive) {
  if (user.role.isAdmin) return sessionActive ?? '';
  final memberships = user.companyMemberships;
  if (memberships.length == 1) return memberships.first;
  if (sessionActive != null && memberships.contains(sessionActive)) {
    return sessionActive;
  }
  // Default to the first membership — strictly self-consistent with the list
  // the UI shows, so a malformed doc whose primary [AppUser.companyId] is not
  // in [companyMemberships] can never resolve to an id outside that list.
  return memberships.first;
}
