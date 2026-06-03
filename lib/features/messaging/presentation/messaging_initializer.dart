import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_keys.dart';
import '../../../core/config/app_secrets.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../notifications/presentation/alerts_screen.dart';
import 'messaging_providers.dart';

class MessagingInitializer extends ConsumerStatefulWidget {
  final Widget child;
  const MessagingInitializer({super.key, required this.child});
  @override
  ConsumerState<MessagingInitializer> createState() =>
      _MessagingInitializerState();
}

class _MessagingInitializerState extends ConsumerState<MessagingInitializer> {
  bool _wired = false;
  String? _identityUid;
  Future<void> _chain = Future.value();

  void _scheduleOnUser(AppUser? user) {
    _chain = _chain.then((_) => _onUser(user)).catchError((_) {});
  }

  @override
  void initState() {
    super.initState();
    // Fire on the initial emission too (not only on changes), mirroring the
    // router's fireImmediately listener for the same provider. Inside a
    // ConsumerState this must use listenManual; WidgetRef.listen (used in
    // build) does not support fireImmediately.
    ref.listenManual<AsyncValue<AppUser?>>(
      currentUserProvider,
      (_, next) => _scheduleOnUser(next.valueOrNull),
      fireImmediately: true,
    );
  }

  Future<void> _ensureInit() async {
    if (_wired || !AppSecrets.hasOneSignal) return;
    _wired = true;
    final svc = ref.read(oneSignalServiceProvider);
    await svc.init(AppSecrets.oneSignalAppId);
    await svc.requestPermission();
    svc.onForeground((title, body) {
      final text = title ?? body ?? 'New notification';
      scaffoldMessengerKey.currentState
          ?.showSnackBar(SnackBar(content: Text(text)));
    });
    svc.onClick(() {
      rootNavigatorKey.currentState
          ?.push(MaterialPageRoute(builder: (_) => const AlertsScreen()));
    });
  }

  Future<void> _onUser(AppUser? user) async {
    await _ensureInit();
    if (!AppSecrets.hasOneSignal) return;
    final svc = ref.read(oneSignalServiceProvider);
    if (user == null) {
      if (_identityUid != null) {
        _identityUid = null;
        await svc.logout();
      }
      return;
    }
    if (_identityUid == user.uid) return;
    _identityUid = user.uid;
    await svc.login(user.uid);
    await svc.setAudienceTags(companyId: user.companyId, role: user.role.name);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
