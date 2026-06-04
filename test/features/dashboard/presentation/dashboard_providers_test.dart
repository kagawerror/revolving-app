import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/companies/domain/fund_repository.dart';
import 'package:rev_app/features/companies/presentation/admin_providers.dart';
import 'package:rev_app/features/dashboard/presentation/dashboard_providers.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_repository.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';
import 'package:rev_app/features/replenishment/presentation/replenishment_providers.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_repository.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/approver_inbox_providers.dart';
import 'package:rev_app/features/requests/presentation/request_providers.dart';

Fund _fund(String id, String companyId, String name) => Fund(
      id: id,
      companyId: companyId,
      name: name,
      originalBudget: Money.fromCentavos(100),
      availableBalance: Money.fromCentavos(100),
      lowBalanceThresholdPct: 3,
      status: FundStatus.active,
    );

/// Returns deliberately distinct lists for the two read paths so a test can
/// tell which query the dashboard chose for the current role.
class _FakeFundRepo implements FundRepository {
  static final all = [_fund('a', 'c1', 'A'), _fund('b', 'c2', 'B')];
  static final company = [_fund('c', 'c1', 'C')];

  @override
  Stream<List<Fund>> watchAll() => Stream.value(all);
  @override
  Stream<List<Fund>> watchByCompany(String companyId) => Stream.value(company);
  @override
  Stream<Fund?> watchById(String fundId) => const Stream.empty();
  @override
  Future<Result<void>> create(Fund fund) async => const Ok(null);
  @override
  Future<Result<void>> updateDetails({
    required String fundId,
    required String name,
    required int lowBalanceThresholdPct,
  }) async => const Ok(null);
  @override
  Future<Result<void>> adjustBudget({
    required String fundId,
    required Money newBudget,
    required String actorUid,
    required String note,
  }) async => const Ok(null);
}

FundRequest _req(String id, String companyId, RequestStatus status) =>
    FundRequest(
      id: id,
      companyId: companyId,
      fundId: 'f',
      createdByUid: 'u',
      beneficiaryName: 'B',
      amount: Money.fromCentavos(100),
      purpose: 'x',
      proofImageUrl: 'http://img',
      status: status,
    );

/// Distinct lists per read path so the test can tell which query was chosen.
class _FakeRequestRepo implements RequestRepository {
  static final allPending = [
    _req('a', 'c1', RequestStatus.pendingAck),
    _req('b', 'c2', RequestStatus.pendingAck),
  ];
  static final companyPending = [_req('c', 'c1', RequestStatus.pendingAck)];
  static final allRecent = [
    _req('r1', 'c1', RequestStatus.released),
    _req('r2', 'c2', RequestStatus.acknowledged),
  ];
  static final companyRecent = [_req('r3', 'c1', RequestStatus.released)];

  @override
  Stream<List<FundRequest>> watchByStatus(String companyId, RequestStatus status) =>
      Stream.value(companyPending);
  @override
  Stream<List<FundRequest>> watchByStatusAll(RequestStatus status) =>
      Stream.value(allPending);
  @override
  Stream<List<FundRequest>> watchRecentByCompany(String companyId, int limit) =>
      Stream.value(companyRecent);
  @override
  Stream<List<FundRequest>> watchRecentAll(int limit) => Stream.value(allRecent);

  @override
  Stream<List<FundRequest>> watchByFund(String fundId) => const Stream.empty();
  @override
  Future<Result<String>> create(FundRequest request) async => const Ok('');
  @override
  Future<Result<void>> transition({
    required FundRequest request,
    required RequestStatus to,
    required String actorUid,
    String? note,
  }) async => const Ok(null);
  @override
  Future<Result<void>> release({
    required FundRequest request,
    required String actorUid,
  }) async => const Ok(null);
}

Replenishment _repl(String id, String companyId) => Replenishment(
      id: id,
      companyId: companyId,
      fundId: 'f',
      status: ReplenishmentStatus.submitted,
      requestIds: const ['r'],
      total: Money.fromCentavos(100),
      reportNotes: '',
      createdByUid: 'u',
    );

class _FakeReplenishmentRepo implements ReplenishmentRepository {
  static final allPending = [_repl('a', 'c1'), _repl('b', 'c2')];
  static final companyPending = [_repl('c', 'c1')];

  @override
  Stream<List<Replenishment>> watchByCompanyAndStatus(
          String companyId, String status) =>
      Stream.value(companyPending);
  @override
  Stream<List<Replenishment>> watchByStatusAll(String status) =>
      Stream.value(allPending);

  @override
  Stream<List<Replenishment>> watchByFund(String fundId) => const Stream.empty();
  @override
  Future<Result<Replenishment>> createDraft(
          {required String fundId, required String createdByUid}) async =>
      const Err(ValidationFailure('unused'));
  @override
  Future<Result<void>> submit(
          {required Replenishment replenishment,
          required String actorUid,
          required String notes}) async =>
      const Ok(null);
  @override
  Future<Result<void>> approve(
          {required Replenishment replenishment, required String actorUid}) async =>
      const Ok(null);
  @override
  Future<Result<void>> reject(
          {required Replenishment replenishment, required String actorUid}) async =>
      const Ok(null);
  @override
  Future<Result<void>> discardDraft(
          {required Replenishment replenishment}) async =>
      const Ok(null);
}

AppUser _user(UserRole role, String companyId) => AppUser(
      uid: 'u',
      companyId: companyId,
      role: role,
      displayName: 'n',
      email: 'e@x.com',
    );

void main() {
  ProviderContainer container(AppUser user) {
    final c = ProviderContainer(overrides: [
      fundRepositoryProvider.overrideWithValue(_FakeFundRepo()),
      requestRepositoryProvider.overrideWithValue(_FakeRequestRepo()),
      replenishmentRepositoryProvider
          .overrideWithValue(_FakeReplenishmentRepo()),
      currentUserProvider.overrideWith((ref) => Stream.value(user)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('admin dashboard funds aggregate across all companies (watchAll)',
      () async {
    final c = container(_user(UserRole.admin, ''));
    c.listen(dashboardFundsProvider, (_, _) {});
    await c.read(currentUserProvider.future);
    await c.read(allFundsProvider.future);
    expect(c.read(dashboardFundsProvider).value, _FakeFundRepo.all);
  });

  test('non-admin dashboard funds are scoped to their own company', () async {
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(dashboardFundsProvider, (_, _) {});
    await c.read(currentUserProvider.future);
    await c.read(companyFundsProvider('c1').future);
    expect(c.read(dashboardFundsProvider).value, _FakeFundRepo.company);
  });

  test('admin dashboard pending requests aggregate across all companies',
      () async {
    final c = container(_user(UserRole.admin, ''));
    c.listen(dashboardPendingRequestsProvider, (_, _) {});
    await c.read(currentUserProvider.future);
    await c.read(allPendingRequestsProvider.future);
    expect(c.read(dashboardPendingRequestsProvider).value,
        _FakeRequestRepo.allPending);
  });

  test('non-admin dashboard pending requests are scoped to their company',
      () async {
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(dashboardPendingRequestsProvider, (_, _) {});
    await c.read(currentUserProvider.future);
    await c.read(pendingRequestsProvider.future);
    expect(c.read(dashboardPendingRequestsProvider).value,
        _FakeRequestRepo.companyPending);
  });

  test('admin dashboard pending replenishments aggregate across all companies',
      () async {
    final c = container(_user(UserRole.admin, ''));
    c.listen(dashboardPendingReplenishmentsProvider, (_, _) {});
    await c.read(currentUserProvider.future);
    await c.read(allPendingReplenishmentsProvider.future);
    expect(c.read(dashboardPendingReplenishmentsProvider).value,
        _FakeReplenishmentRepo.allPending);
  });

  test('non-admin dashboard pending replenishments are scoped to their company',
      () async {
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(dashboardPendingReplenishmentsProvider, (_, _) {});
    await c.read(currentUserProvider.future);
    await c.read(pendingReplenishmentsProvider.future);
    expect(c.read(dashboardPendingReplenishmentsProvider).value,
        _FakeReplenishmentRepo.companyPending);
  });

  test('admin recent requests aggregate across all companies (watchRecentAll)',
      () async {
    final c = container(_user(UserRole.admin, ''));
    c.listen(recentRequestsProvider, (_, _) {});
    await c.read(currentUserProvider.future);
    await c.read(recentRequestsProvider.future);
    expect(c.read(recentRequestsProvider).value, _FakeRequestRepo.allRecent);
  });

  test('non-admin recent requests are scoped to their own company', () async {
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(recentRequestsProvider, (_, _) {});
    await c.read(currentUserProvider.future);
    await c.read(recentRequestsProvider.future);
    expect(c.read(recentRequestsProvider).value, _FakeRequestRepo.companyRecent);
  });
}
