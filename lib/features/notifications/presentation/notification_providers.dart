import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/firebase/firebase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../replenishment/presentation/replenishment_providers.dart';
import '../../requests/presentation/approver_inbox_providers.dart';
import '../data/firestore_notification_repository.dart';
import '../domain/app_notification.dart';
import '../domain/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
    (ref) => FirestoreNotificationRepository(ref.watch(firestoreProvider)));

final myNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  final repo = ref.watch(notificationRepositoryProvider);
  // Admins have no company membership (companyId is empty), so their alerts span
  // every tenant — drop the companyId filter via the cross-company query.
  if (user.role.isAdmin) return repo.watchAllForRole(user.role.name);
  return repo.watchForRole(user.companyId, user.role.name);
});

final unreadCountProvider = Provider<int>((ref) {
  final list = ref.watch(myNotificationsProvider).valueOrNull ?? const [];
  return list.where((n) => n.isUnread).length;
});

/// Approver bell count: ALL pending approvals — submitted replenishment reports
/// PLUS released requests awaiting post-hoc review. Derived purely from the two
/// existing company-scoped streams ([pendingReplenishmentsProvider] = `status ==
/// submitted`; [pendingRequestsProvider] = `status == released`) so it adds no
/// Firestore query or index. Either side loading/empty contributes 0.
final pendingApprovalCountProvider = Provider<int>((ref) {
  final reps = ref.watch(pendingReplenishmentsProvider).valueOrNull?.length ?? 0;
  final reqs = ref.watch(pendingRequestsProvider).valueOrNull?.length ?? 0;
  return reps + reqs;
});
