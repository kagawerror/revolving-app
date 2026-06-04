import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rev_app/core/widgets/profile_menu_button.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/messaging/presentation/messaging_providers.dart';

const _user = AppUser(
  uid: 'u1',
  companyId: 'acme',
  role: UserRole.incharge,
  displayName: 'Jane Doe',
  email: 'jane@acme.test',
  accentId: 'forest',
);

/// Captures whether the [signOutProvider] function was invoked and how often.
class _SignOutSpy {
  int calls = 0;
  Future<void> call() async => calls++;
}

void main() {
  late _SignOutSpy signOut;

  setUp(() {
    signOut = _SignOutSpy();
  });

  /// Builds a router whose home hosts the button in an app bar, plus a
  /// `/profile` route so we can assert navigation from the menu.
  GoRouter buildRouter() => GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              appBar: _HostAppBar(),
              body: SizedBox.shrink(),
            ),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, _) => const Scaffold(
              body: Center(child: Text('PROFILE PAGE')),
            ),
          ),
        ],
      );

  Widget harness({
    required AsyncValue<AppUser?> currentUser,
  }) {
    return ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(currentUser.valueOrNull)),
        signOutProvider.overrideWithValue(signOut.call),
      ],
      child: MaterialApp.router(routerConfig: buildRouter()),
    );
  }

  testWidgets('trigger renders the user display name (discoverability)',
      (tester) async {
    await tester.pumpWidget(harness(currentUser: const AsyncData(_user)));
    await tester.pumpAndSettle();

    // The label is visible in the app bar before opening the menu.
    expect(find.text('Jane Doe'), findsOneWidget);
  });

  testWidgets('tapping the trigger opens a menu with Profile and Sign out',
      (tester) async {
    await tester.pumpWidget(harness(currentUser: const AsyncData(_user)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ProfileMenuButton));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);

    // Header renders identity: email plus the capitalized role label. Guards
    // against silent regressions in _roleLabel / the email branch.
    expect(find.text('jane@acme.test'), findsOneWidget);
    expect(find.text('Incharge'), findsOneWidget);
  });

  testWidgets('tapping Sign out invokes the signOut function once',
      (tester) async {
    await tester.pumpWidget(harness(currentUser: const AsyncData(_user)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ProfileMenuButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(signOut.calls, 1);
  });

  testWidgets('tapping Profile navigates to /profile', (tester) async {
    await tester.pumpWidget(harness(currentUser: const AsyncData(_user)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ProfileMenuButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('PROFILE PAGE'), findsOneWidget);
  });

  testWidgets('null/loading user falls back to "Account" and does not throw',
      (tester) async {
    await tester.pumpWidget(harness(currentUser: const AsyncData(null)));
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The menu still opens and offers Profile + Sign out without a header.
    await tester.tap(find.byType(ProfileMenuButton));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });
}

/// App bar that hosts the widget under test as its sole action.
class _HostAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _HostAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('Home'),
      actions: const [ProfileMenuButton()],
    );
  }
}
