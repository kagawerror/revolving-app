import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_keys.dart';
import '../features/auth/domain/app_user.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/bootstrap_screen.dart';
import '../features/auth/presentation/change_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/admin_users/presentation/user_admin_screen.dart';
import '../features/companies/presentation/adjust_fund_screen.dart';
import '../features/companies/presentation/create_fund_screen.dart';
import '../features/config/presentation/cloudinary_config_screen.dart';
import '../features/fund_audit/presentation/fund_audit_create_screen.dart';
import '../features/fund_audit/presentation/fund_audit_detail_screen.dart';
import '../features/fund_audit/presentation/fund_audit_list_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/reports/presentation/report_screen.dart';
import '../features/requests/presentation/acknowledged_worklist_screen.dart';
import '../features/requests/presentation/conflict_worklist_screen.dart';
import '../features/requests/presentation/create_request_screen.dart';
import '../features/requests/presentation/post_release_review_screen.dart';
import 'role_shell_screen.dart';

@visibleForTesting
String homeFor(UserRole role) => switch (role) {
      UserRole.admin => '/admin',
      UserRole.incharge => '/incharge',
      _ when role.canApprove => '/approvals',
      _ => '/incharge', // employees view their requests under the incharge shell in v1
    };

/// Pure redirect decision (extracted so it is testable without Firebase).
///
/// Returns the path to redirect to, or `null` to stay put. While auth is still
/// loading we return `null` to avoid a flicker. `/login` and `/setup` are the
/// two valid signed-out destinations; signed-in users are always pushed to
/// their role home off either of them.
@visibleForTesting
String? redirectFor({
  required AsyncValue<AppUser?> auth,
  required String location,
}) {
  if (auth.isLoading) return null;
  final user = auth.valueOrNull;
  final onAuthScreen = location == '/login' || location == '/setup';
  if (user == null) return onAuthScreen ? null : '/login';

  // Forced password rotation: a signed-in user carrying `mustChangePassword`
  // (admin-created or admin-reset) is gated to /change-password until they set a
  // new password. This precedes ALL role routing so no role home can dodge it.
  // The gate itself is reachable (return null when already there).
  if (user.mustChangePassword) {
    return location == '/change-password' ? null : '/change-password';
  }
  // Conversely, a user who is NOT forced should not linger on the gate: send
  // them to their role home.
  if (location == '/change-password') return homeFor(user.role);

  final home = homeFor(user.role);
  if (onAuthScreen) return home;

  // Admin is a superuser: it operates the incharge + approval workflows in any
  // company on top of admin maintenance, so it may visit any signed-in route
  // without being bounced back to /admin (homeFor still lands it on /admin).
  if (user.role.isAdmin) return null;

  // View-restricted worklist: ONLY incharge (and admin, already passed above)
  // may see /incharge/acknowledged. An employee shares the /incharge shell, so
  // the prefix guard below would admit it; bounce any non-incharge back home.
  if (location.startsWith('/incharge/acknowledged') &&
      user.role != UserRole.incharge) {
    return home;
  }

  // View-restricted conflicts queue: ONLY incharge (and admin, already passed
  // above) may resolve overdraft conflicts — it moves money. An employee shares
  // the /incharge shell, so the prefix guard below would admit it; bounce any
  // non-incharge back home.
  if (location.startsWith('/incharge/conflicts') &&
      user.role != UserRole.incharge) {
    return home;
  }

  // Fund audit VIEW is open to any signed-in same-company role (approvers
  // review counts, incharge/admin also create). It nominally sits under the
  // /incharge subtree, so without this an approver landing on /approvals would
  // be bounced. CREATE (/incharge/audit/new) is separately gated by the route's
  // own redirect (_auditCreateGuard); Firestore rules enforce the real
  // company/role boundary on writes.
  if (location.startsWith('/incharge/audit')) return null;

  // Reports is a shared route (no role shell owns it) but role-gated: only
  // admin/ceo/incharge (canViewReports) may enter. A permitted role passes
  // through; everyone else bounces home. Admin already returned above.
  if (location.startsWith('/reports')) {
    return user.role.canViewReports ? null : home;
  }

  // Shared routes (e.g. /profile) belong to no role shell, so the role-home
  // guard must let them through. Anything else: a signed-in user may only stay
  // inside their own role subtree; foreign/unknown routes bounce back home.
  if (_sharedSignedInRoutes.any(location.startsWith)) return null;
  return location.startsWith(home) ? null : home;
}

/// Routes any signed-in user may visit regardless of role — no role shell owns
/// them, so the role-home redirect must not bounce them away. `/reports` is
/// handled separately above (it is role-gated, not universally shared).
const _sharedSignedInRoutes = <String>['/profile'];

/// Whether [role] may CREATE a cash count. The single source of truth for the
/// audit create permission: both the create-route guard and the list screen's
/// "New count" CTA read it, so the CTA shows iff create is actually allowed.
/// (incharge custodian or admin — mirrors [UserRole.canManageFundOrAdmin].)
@visibleForTesting
bool canCreateAudit(UserRole? role) => role != null && role.canManageFundOrAdmin;

/// Gate the create-audit route to the incharge custodian or an admin. Other
/// roles (e.g. approvers who may VIEW) are bounced to the audit list, carrying
/// the same query params. Returns a redirect path, or `null` to allow.
String? _auditCreateGuard(Ref ref, GoRouterState state) {
  final user = ref.read(currentUserProvider).valueOrNull;
  if (user == null) return null; // redirectFor handles signed-out.
  if (canCreateAudit(user.role)) return null;
  final qp = state.uri.query;
  return '/incharge/audit${qp.isEmpty ? '' : '?$qp'}';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Bridge the auth stream to a Listenable so the router is built once.
  final refresh = ValueNotifier<AsyncValue<AppUser?>>(const AsyncLoading());
  ref.onDispose(refresh.dispose);
  ref.listen<AsyncValue<AppUser?>>(
    currentUserProvider,
    (_, next) => refresh.value = next,
    fireImmediately: true,
  );

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(
      auth: refresh.value,
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/setup', builder: (context, _) => const BootstrapScreen()),
      GoRoute(
        // Forced first-login / post-reset password gate. redirectFor lands the
        // user here whenever their profile carries mustChangePassword.
        path: '/change-password',
        builder: (_, _) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (_, _) => const RoleShellScreen(role: UserRole.admin),
      ),
      GoRoute(
        path: '/admin/create-fund',
        builder: (_, _) => const CreateFundScreen(),
      ),
      GoRoute(
        path: '/admin/users',
        builder: (_, _) => const UserAdminScreen(),
      ),
      GoRoute(
        path: '/admin/cloudinary',
        builder: (_, _) => const CloudinaryConfigScreen(),
      ),
      GoRoute(
        path: '/incharge',
        // The shell computes showAcknowledged from currentUserProvider
        // (role.canManageFundOrAdmin), so an employee sharing this route gets no
        // Worklist tab even though the route role is incharge.
        builder: (_, _) => const RoleShellScreen(role: UserRole.incharge),
      ),
      GoRoute(
        path: '/incharge/create',
        builder: (_, _) => const CreateRequestScreen(),
      ),
      GoRoute(
        path: '/incharge/acknowledged',
        builder: (_, _) => const AcknowledgedWorklistScreen(),
      ),
      GoRoute(
        // Incharge overdraft-resolution queue. View-restricted to incharge/admin
        // by redirectFor (an employee sharing the /incharge shell is bounced).
        path: '/incharge/conflicts',
        builder: (_, _) => const ConflictWorklistScreen(),
      ),
      // Fund audit (proof-of-cash). companyId/fundId travel as query params;
      // the entry point (the incharge fund list) supplies them. VIEW is open to
      // any same-company role so approvers can review; CREATE is gated below.
      GoRoute(
        path: '/incharge/audit',
        builder: (_, state) {
          // CREATE is permitted iff the caller could pass _auditCreateGuard, so
          // view-only roles never see a dead-end "New count" CTA.
          final role = ref.read(currentUserProvider).valueOrNull?.role;
          return FundAuditListScreen(
            companyId: state.uri.queryParameters['companyId'] ?? '',
            fundId: state.uri.queryParameters['fundId'] ?? '',
            canCreate: canCreateAudit(role),
          );
        },
      ),
      GoRoute(
        path: '/incharge/audit/new',
        // Create is for the incharge custodian (admins may also count).
        redirect: (context, state) => _auditCreateGuard(ref, state),
        builder: (_, state) => FundAuditCreateScreen(
          companyId: state.uri.queryParameters['companyId'] ?? '',
          fundId: state.uri.queryParameters['fundId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/incharge/audit/:id',
        builder: (_, state) =>
            FundAuditDetailScreen(auditId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/approvals',
        // ceo maps to the approver shell (role.canApprove); the shell only needs
        // to know this is the "approvals" shell, not the exact approver role.
        builder: (_, _) => const RoleShellScreen(role: UserRole.ceo),
      ),
      GoRoute(
        // Approver post-release review queue. Lives under the /approvals
        // subtree, so the role-home prefix guard in redirectFor already keeps
        // non-approvers out (admin passes via the superuser bypass).
        path: '/approvals/review',
        builder: (_, _) => const PostReleaseReviewScreen(),
      ),
      GoRoute(
        // Fund Adjustment entry for CEO/admin. Under the /approvals subtree so
        // the role-home prefix guard keeps non-approvers out; the screen itself
        // re-checks canAdjustFund (admin || ceo) as a fail-safe. A CEO (approver
        // but NOT admin) reaches it via the Approvals AppBar action.
        path: '/approvals/adjust-fund',
        builder: (_, _) => const AdjustFundScreen(),
      ),
      GoRoute(
        // Standalone Reports surface. Role-gated in redirectFor on
        // canViewReports (admin/ceo/incharge); the screen re-checks as a
        // fail-safe. Reached via the Reports AppBar action on each home shell.
        path: '/reports',
        builder: (_, _) => const ReportScreen(),
      ),
      GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen()),
    ],
  );
});
