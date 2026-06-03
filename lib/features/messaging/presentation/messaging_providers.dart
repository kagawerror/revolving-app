import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/messaging/onesignal_service.dart';
import '../../auth/presentation/auth_providers.dart';

final oneSignalServiceProvider =
    Provider<OneSignalService>((ref) => OneSignalService());

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
