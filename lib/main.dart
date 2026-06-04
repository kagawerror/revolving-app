import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_keys.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/messaging/presentation/messaging_initializer.dart';
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
