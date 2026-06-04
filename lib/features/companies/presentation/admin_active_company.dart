import '../../auth/domain/app_user.dart';

/// Resolves the company a [user] is operating in.
///
/// Regular roles are pinned to their own [AppUser.companyId]. An **admin** has
/// an empty `companyId` and is a superuser that may operate any company, so its
/// scope is driven by the in-session [adminActive] selection (the value behind
/// `adminActiveCompanyProvider`). When an admin has not yet picked a company,
/// this returns `''` and callers should no-op their company-scoped streams.
///
/// Pure + top-level on purpose: it's the unit-testable seam for company scoping
/// without dragging in widgets or Riverpod.
String effectiveCompanyId(AppUser user, String? adminActive) =>
    user.role.isAdmin ? (adminActive ?? '') : user.companyId;
