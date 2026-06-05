import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_keys.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/domain/app_user.dart';
import 'features/auth/presentation/auth_providers.dart';
import 'features/messaging/presentation/messaging_initializer.dart';
import 'features/welcome/domain/welcome_arming.dart';
import 'features/welcome/presentation/welcome_gate.dart';
import 'routing/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android initializes from google-services.json via the Gradle plugin, so no
  // options are needed here. iOS, however, requires platform options: run
  // `flutterfire configure` (it generates the gitignored lib/firebase_options.dart
  // plus the iOS GoogleService-Info.plist), then switch this call to
  // `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`.
  await Firebase.initializeApp();
  runApp(const ProviderScope(child: RevApp()));
}

class RevApp extends ConsumerWidget {
  const RevApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-arm the welcome greeting on every new signed-in identity (login or a
    // user switch) so a fresh login shows the welcome before the app, not just
    // cold start / sign-out. Re-emits of the same user and sign-out are inert
    // (see shouldRearmWelcome); sign-out arming stays owned by signOutProvider.
    ref.listen<AsyncValue<AppUser?>>(currentUserProvider, (prev, next) {
      if (shouldRearmWelcome(prev?.valueOrNull, next.valueOrNull)) {
        ref.read(welcomeDismissedProvider.notifier).state = false;
      }
    });

    final router = ref.watch(routerProvider);
    final theme = ref.watch(themeControllerProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Revolving Fund',
      theme: AppTheme.light(theme.seed),
      darkTheme: AppTheme.dark(theme.seed),
      themeMode: theme.mode,
      routerConfig: router,
      scaffoldMessengerKey: scaffoldMessengerKey,
      builder: (context, child) => WelcomeGate(
        child: MessagingInitializer(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
