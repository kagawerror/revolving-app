import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_secrets.dart';
import '../../../services/messaging/onesignal_service.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/http_push_sender.dart';
import '../domain/push_sender.dart';

final oneSignalServiceProvider =
    Provider<OneSignalService>((ref) => OneSignalService());

final pushSenderProvider = Provider<PushSender>((ref) => HttpPushSender(
      relayUrl: AppSecrets.pushRelayUrl,
      relayToken: AppSecrets.pushRelayToken,
    ));

final signOutProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    try {
      await ref.read(oneSignalServiceProvider).logout();
    } catch (_) {
      // best-effort; sign out regardless
    }
    await ref.read(authRepositoryProvider).signOut();
  };
});
