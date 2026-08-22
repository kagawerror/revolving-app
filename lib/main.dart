import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_keys.dart';
import 'features/sync/presentation/sync_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/domain/app_user.dart';
import 'features/auth/presentation/auth_providers.dart';
import 'features/messaging/presentation/messaging_initializer.dart';
import 'features/update/presentation/update_gate.dart';
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
  // Offline-first: persist Firestore locally so reads/writes work without a
  // connection and replay on reconnect. Unlimited cache so a long offline
  // session (queued releases, cached worklists) is never silently evicted.
  //
  // NOTE: this is the one documented, sanctioned exception to the
  // "no FirebaseFirestore.instance outside firebase_providers.dart" rule.
  // Persistence MUST be configured on the singleton before any provider builds
  // a Firestore-backed repository, so it has to happen here at startup rather
  // than behind the firestoreProvider DI seam.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  // Resolve SharedPreferences once at startup so the offline outbox store can be
  // injected synchronously (see sharedPreferencesProvider's bootstrap contract).
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const RevApp(),
    ),
  );
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

    // Offline sync: drain the outbox on the offline → online edge (uploads
    // pending images, backfills create proofs, replays captured releases
    // through the server-side confirm transaction). Wired once at the app root.
    wireSyncOnReconnect(ref);

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
      builder: (context, child) => UpdateGate(
        child: WelcomeGate(
          child: MessagingInitializer(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
