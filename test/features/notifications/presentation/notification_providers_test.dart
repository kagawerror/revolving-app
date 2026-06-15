import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/notifications/domain/app_notification.dart';
import 'package:rev_app/features/notifications/domain/notification_repository.dart';
import 'package:rev_app/features/notifications/presentation/notification_providers.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';
import 'package:rev_app/features/replenishment/presentation/replenishment_providers.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/approver_inbox_providers.dart';

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
  Stream<List<AppNotification>> watchAllForRole(String r) => const Stream.empty();
  @override
  Future<void> markRead(String id) async {}
}

/// Records which method [myNotificationsProvider] dispatched to (and its args)
/// so we can prove admin → cross-company, everyone else → company-scoped.
class _RecordingRepo implements NotificationRepository {
  String? watchAllRole;
  String? watchForCompany;
  String? watchForRoleArg;

  @override
  Stream<List<AppNotification>> watchForRole(String c, String r) {
    watchForCompany = c;
    watchForRoleArg = r;
    return Stream.value(const []);
  }

  @override
  Stream<List<AppNotification>> watchAllForRole(String r) {
    watchAllRole = r;
    return Stream.value(const []);
  }

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

  Replenishment submitted(String id) => Replenishment(
        id: id,
        companyId: 'c1',
        fundId: 'f1',
        status: ReplenishmentStatus.submitted,
        requestIds: const ['r'],
        total: Money.fromCentavos(1000),
        reportNotes: '',
        createdByUid: 'inc',
      );

  FundRequest released(String id) => FundRequest(
        id: id,
        companyId: 'c1',
        fundId: 'f1',
        createdByUid: 'inc',
        beneficiaryName: 'Ben',
        amount: Money.fromCentavos(1000),
        purpose: 'x',
        proofImageUrl: 'https://img/x.jpg',
        status: RequestStatus.released,
      );

  test('pendingApprovalCountProvider sums submitted reports + released requests',
      () async {
    final container = ProviderContainer(overrides: [
      pendingReplenishmentsProvider.overrideWith(
          (ref) => Stream.value([submitted('a'), submitted('b'), submitted('c')])),
      pendingRequestsProvider
          .overrideWith((ref) => Stream.value([released('r1'), released('r2')])),
    ]);
    addTearDown(container.dispose);
    container.listen(pendingApprovalCountProvider, (_, _) {});
    await container.read(pendingReplenishmentsProvider.future);
    await container.read(pendingRequestsProvider.future);
    // 3 reports + 2 released requests = 5.
    expect(container.read(pendingApprovalCountProvider), 5);
  });

  test('pendingApprovalCountProvider is 0 while both sides load', () {
    final container = ProviderContainer(overrides: [
      pendingReplenishmentsProvider
          .overrideWith((ref) => const Stream.empty()),
      pendingRequestsProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(container.dispose);
    container.listen(pendingApprovalCountProvider, (_, _) {});
    expect(container.read(pendingApprovalCountProvider), 0);
  });

  test('pendingApprovalCountProvider is 0 for two empty lists', () {
    final container = ProviderContainer(overrides: [
      pendingReplenishmentsProvider
          .overrideWith((ref) => Stream.value(const [])),
      pendingRequestsProvider.overrideWith((ref) => Stream.value(const [])),
    ]);
    addTearDown(container.dispose);
    container.listen(pendingApprovalCountProvider, (_, _) {});
    expect(container.read(pendingApprovalCountProvider), 0);
  });

  Future<_RecordingRepo> dispatchFor(AppUser user) async {
    final repo = _RecordingRepo();
    final container = ProviderContainer(overrides: [
      notificationRepositoryProvider.overrideWithValue(repo),
      currentUserProvider.overrideWith((ref) => Stream.value(user)),
    ]);
    addTearDown(container.dispose);
    container.listen(myNotificationsProvider, (_, _) {});
    await container.read(currentUserProvider.future);
    await container.read(myNotificationsProvider.future);
    return repo;
  }

  test('myNotificationsProvider uses watchAllForRole (cross-company) for admin',
      () async {
    // Admin has no company membership — companyId is empty.
    final repo = await dispatchFor(const AppUser(
      uid: 'a',
      companyId: '',
      role: UserRole.admin,
      displayName: 'A',
      email: 'a@x.com',
    ));
    expect(repo.watchAllRole, 'admin');
    // The company-scoped path must NOT be taken for admin.
    expect(repo.watchForCompany, isNull);
  });

  test('myNotificationsProvider uses watchForRole (company-scoped) for approver',
      () async {
    final repo = await dispatchFor(const AppUser(
      uid: 'm',
      companyId: 'c1',
      role: UserRole.manager,
      displayName: 'M',
      email: 'm@x.com',
    ));
    expect(repo.watchForCompany, 'c1');
    expect(repo.watchForRoleArg, 'manager');
    expect(repo.watchAllRole, isNull);
  });

  test('myNotificationsProvider uses watchForRole (company-scoped) for incharge',
      () async {
    final repo = await dispatchFor(const AppUser(
      uid: 'i',
      companyId: 'c1',
      role: UserRole.incharge,
      displayName: 'I',
      email: 'i@x.com',
    ));
    expect(repo.watchForCompany, 'c1');
    expect(repo.watchForRoleArg, 'incharge');
    expect(repo.watchAllRole, isNull);
  });
}
