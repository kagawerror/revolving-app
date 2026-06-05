import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_secrets.dart';
import '../../../services/messaging/onesignal_service.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../../welcome/presentation/welcome_gate.dart';
import '../data/http_push_sender.dart';
import '../domain/push_sender.dart';

final oneSignalServiceProvider =
    Provider<OneSignalService>((ref) => OneSignalService());

final pushSenderProvider = Provider<PushSender>((ref) {
  if (!AppSecrets.hasPushRelay) return const NoopPushSender();
  return HttpPushSender(
    relayUrl: AppSecrets.pushRelayUrl,
    relayToken: AppSecrets.pushRelayToken,
  );
});

final signOutProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    try {
      await ref.read(oneSignalServiceProvider).logout();
    } catch (_) {
      // best-effort; sign out regardless
    }
    // Drop any per-session admin state so the next account doesn't inherit a
    // stale operating-company selection. currentUserProvider rebuilds will
    // re-scope role-gated widgets, but the StateProvider holding the admin's
    // pick lives on the root container and would otherwise survive the swap.
    ref.invalidate(adminActiveCompanyProvider);
    // Re-arm the welcome overlay so signing out returns to the greeting (the
    // login screen sits beneath it). The flag is in-memory and only otherwise
    // resets on a cold start, so without this the next user lands on /login
    // with no welcome.
    ref.invalidate(welcomeDismissedProvider);
    await ref.read(authRepositoryProvider).signOut();
  };
});
