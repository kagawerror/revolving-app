import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/domain/app_user.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/companies/presentation/admin_home_screen.dart';
import '../features/requests/presentation/approver_home_screen.dart';
import '../features/requests/presentation/incharge_home_screen.dart';

String _homeFor(UserRole role) => switch (role) {
      UserRole.admin => '/admin',
      UserRole.incharge => '/incharge',
      _ when role.canApprove => '/approvals',
      _ => '/incharge', // employees view their requests under the incharge shell in v1
    };

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(currentUserProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/login';
      final user = auth.valueOrNull;
      if (auth.isLoading) return null;
      if (user == null) return loggingIn ? null : '/login';
      final home = _homeFor(user.role);
      // Block cross-role access: send everyone to their own home.
      if (loggingIn) return home;
      final allowed = home == state.matchedLocation;
      return allowed ? null : home;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminHomeScreen()),
      GoRoute(path: '/incharge', builder: (_, __) => const InchargeHomeScreen()),
      GoRoute(path: '/approvals', builder: (_, __) => const ApproverHomeScreen()),
    ],
  );
});
