import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rev_app/app_keys.dart';
import 'package:rev_app/features/update/domain/app_version_info.dart';
import 'package:rev_app/features/update/domain/update_decision.dart';
import 'package:rev_app/features/update/presentation/update_gate.dart';
import 'package:rev_app/features/update/presentation/update_providers.dart';

const _latest = AppVersionInfo(
  versionCode: 9,
  versionName: '9.0.0',
  apkUrl: 'https://example.com/rev_app-9.0.0+9.apk',
  notes: 'Brand new.',
);

void main() {
  // Reproduces the real wiring from main.dart: UpdateGate lives in
  // MaterialApp.router's `builder`, which is ABOVE the router's Navigator.
  // showDialog must still find a Navigator (via rootNavigatorKey) or the prompt
  // silently never appears — which is exactly what happened on real devices.
  testWidgets('shows the update dialog from the builder position (above the router navigator)',
      (tester) async {
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateCheckProvider.overrideWith(
            (ref) async =>
                const UpdateDecision(UpdateStatus.updateAvailable, _latest),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) =>
              UpdateGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Update available (9.0.0)'), findsOneWidget);
  });
}
