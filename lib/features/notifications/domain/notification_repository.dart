import 'app_notification.dart';

abstract interface class NotificationRepository {
  Stream<List<AppNotification>> watchForRole(String companyId, String role);
  Future<void> markRead(String id);
}
