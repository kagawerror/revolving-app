import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Thin wrapper over OneSignal for init, identity, tags, and listeners.
class OneSignalService {
  bool _initialized = false;

  Future<void> init(String appId) async {
    if (_initialized || appId.isEmpty) return;
    OneSignal.initialize(appId);
    _initialized = true;
  }

  Future<bool> requestPermission() =>
      OneSignal.Notifications.requestPermission(true);

  Future<void> login(String externalId) => OneSignal.login(externalId);
  Future<void> logout() => OneSignal.logout();

  Future<void> setAudienceTags({
    required String companyId,
    required String role,
  }) =>
      OneSignal.User.addTags({'company_id': companyId, 'role': role});

  /// Foreground: prevent the default OS display and forward the title/body.
  void onForeground(void Function(String? title, String? body) handler) {
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      event.preventDefault();
      handler(event.notification.title, event.notification.body);
    });
  }

  void onClick(void Function() handler) {
    OneSignal.Notifications.addClickListener((event) => handler());
  }
}
