import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/firebase/firebase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../replenishment/presentation/replenishment_providers.dart';
import '../data/firestore_notification_repository.dart';
import '../domain/app_notification.dart';
import '../domain/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
    (ref) => FirestoreNotificationRepository(ref.watch(firestoreProvider)));

final myNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref.watch(notificationRepositoryProvider).watchForRole(user.companyId, user.role.name);
});

final unreadCountProvider = Provider<int>((ref) {
  final list = ref.watch(myNotificationsProvider).valueOrNull ?? const [];
  return list.where((n) => n.isUnread).length;
});

/// Approver bell count: how many replenishment reports await this approver's
/// decision. Derived purely from the existing [pendingReplenishmentsProvider]
/// stream (company-scoped `status == submitted`) — adds no Firestore query or
/// index. Loading/empty resolves to 0.
final pendingApprovalCountProvider = Provider<int>((ref) {
  return ref.watch(pendingReplenishmentsProvider).valueOrNull?.length ?? 0;
});
