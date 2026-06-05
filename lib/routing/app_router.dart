import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_keys.dart';
import '../features/auth/domain/app_user.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/bootstrap_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/admin_users/presentation/user_admin_screen.dart';
import '../features/companies/presentation/create_fund_screen.dart';
import '../features/config/presentation/cloudinary_config_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/requests/presentation/acknowledged_worklist_screen.dart';
import '../features/requests/presentation/create_request_screen.dart';
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

  // Shared routes (e.g. /profile) belong to no role shell, so the role-home
  // guard must let them through. Anything else: a signed-in user may only stay
  // inside their own role subtree; foreign/unknown routes bounce back home.
  if (_sharedSignedInRoutes.any(location.startsWith)) return null;
  return location.startsWith(home) ? null : home;
}

/// Routes any signed-in user may visit regardless of role — no role shell owns
/// them, so the role-home redirect must not bounce them away.
const _sharedSignedInRoutes = <String>['/profile'];

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
        path: '/approvals',
        // ceo maps to the approver shell (role.canApprove); the shell only needs
        // to know this is the "approvals" shell, not the exact approver role.
        builder: (_, _) => const RoleShellScreen(role: UserRole.ceo),
      ),
      GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen()),
    ],
  );
});
