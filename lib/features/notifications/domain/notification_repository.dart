import 'app_notification.dart';

abstract interface class NotificationRepository {
  Stream<List<AppNotification>> watchForRole(String companyId, String role);

  /// Cross-company fan-out for admins, who have no single company membership:
  /// every alert addressed to [role] across all tenants, newest-first. Drops the
  /// companyId filter that [watchForRole] applies.
  Stream<List<AppNotification>> watchAllForRole(String role);

  Future<void> markRead(String id);
}
