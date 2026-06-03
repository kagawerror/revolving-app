import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/notifications/domain/app_notification.dart';
import 'package:rev_app/features/notifications/domain/notification_repository.dart';
import 'package:rev_app/features/notifications/presentation/notification_providers.dart';

class _FakeRepo implements NotificationRepository {
  @override
  Stream<List<AppNotification>> watchForRole(String c, String r) => Stream.value([
        AppNotification(
            id: '1',
            companyId: c,
            recipientRoles: const ['incharge'],
            type: 'lowBalance',
            title: 't',
            body: 'b',
            readAt: null),
        AppNotification(
            id: '2',
            companyId: c,
            recipientRoles: const ['incharge'],
            type: 'lowBalance',
            title: 't',
            body: 'b',
            readAt: Timestamp.fromMillisecondsSinceEpoch(1)),
      ]);
  @override
  Future<void> markRead(String id) async {}
}

void main() {
  test('unreadCountProvider counts only unread', () async {
    final container = ProviderContainer(overrides: [
      notificationRepositoryProvider.overrideWithValue(_FakeRepo()),
      currentUserProvider.overrideWith((ref) => Stream.value(const AppUser(
            uid: 'u',
            companyId: 'c1',
            role: UserRole.incharge,
            displayName: 'I',
            email: 'i@x.com',
          ))),
    ]);
    addTearDown(container.dispose);
    // Keep providers alive so they re-evaluate as the user stream emits.
    container.listen(myNotificationsProvider, (prev, next) {});
    container.listen(unreadCountProvider, (prev, next) {});
    // Wait for the user stream to emit, then for notifications to load.
    await container.read(currentUserProvider.future);
    await container.read(myNotificationsProvider.future);
    expect(container.read(unreadCountProvider), 1);
  });
}
