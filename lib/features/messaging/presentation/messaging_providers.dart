import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_secrets.dart';
import '../../../services/messaging/onesignal_service.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
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
    await ref.read(authRepositoryProvider).signOut();
  };
});
