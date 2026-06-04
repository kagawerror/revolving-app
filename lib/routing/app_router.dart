import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_keys.dart';
import '../features/auth/domain/app_user.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/bootstrap_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/companies/presentation/admin_home_screen.dart';
import '../features/companies/presentation/create_fund_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/requests/presentation/approver_home_screen.dart';
import '../features/requests/presentation/create_request_screen.dart';
import '../features/requests/presentation/incharge_home_screen.dart';

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
  return location.startsWith(home) ? null : home;
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
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/setup', builder: (context, _) => const BootstrapScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminHomeScreen()),
      GoRoute(
        path: '/admin/create-fund',
        builder: (_, __) => const CreateFundScreen(),
      ),
      GoRoute(path: '/incharge', builder: (_, __) => const InchargeHomeScreen()),
      GoRoute(
        path: '/incharge/create',
        builder: (_, __) => const CreateRequestScreen(),
      ),
      GoRoute(path: '/approvals', builder: (_, __) => const ApproverHomeScreen()),
      GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen()),
    ],
  );
});
