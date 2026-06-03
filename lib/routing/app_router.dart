import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_keys.dart';
import '../features/auth/domain/app_user.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/companies/presentation/admin_home_screen.dart';
import '../features/companies/presentation/create_fund_screen.dart';
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
    redirect: (context, state) {
      final auth = refresh.value;
      if (auth.isLoading) return null;
      final user = auth.valueOrNull;
      final loggingIn = state.matchedLocation == '/login';
      if (user == null) return loggingIn ? null : '/login';
      final home = homeFor(user.role);
      if (loggingIn) return home;
      return state.matchedLocation.startsWith(home) ? null : home;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
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
    ],
  );
});
