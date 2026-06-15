import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/companies/domain/fund_repository.dart';
import 'package:rev_app/features/companies/presentation/admin_company_context_bar.dart';
import 'package:rev_app/features/companies/presentation/admin_providers.dart';
import 'package:rev_app/features/dashboard/presentation/dashboard_providers.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_repository.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';
import 'package:rev_app/features/replenishment/presentation/replenishment_providers.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_repository.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/sync/domain/release_sync_result.dart';
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
  // Per-company fund lists so a test can prove which companyId the dashboard
  // queried (i.e. that the company picker actually drove the scope).
  static final byCompany = <String, List<Fund>>{
    'c1': company,
    'cA': [_fund('fa', 'cA', 'Fund A')],
    'cB': [_fund('fb', 'cB', 'Fund B')],
  };

  @override
  Stream<List<Fund>> watchAll() => Stream.value(all);
  @override
  Stream<List<Fund>> watchByCompany(String companyId) =>
      Stream.value(byCompany[companyId] ?? const <Fund>[]);
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
  @override
  Future<Result<void>> adjustBalance({
    required String fundId,
    required int signedDeltaCentavos,
    required String reason,
    required String actorUid,
    required UserRole actorRole,
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
    _req('a', 'c1', RequestStatus.created),
    _req('b', 'c2', RequestStatus.created),
  ];
  static final companyPending = [_req('c', 'c1', RequestStatus.created)];
  static final allRecent = [
    _req('r1', 'c1', RequestStatus.released),
    _req('r2', 'c2', RequestStatus.acknowledged),
  ];
  static final companyRecent = [_req('r3', 'c1', RequestStatus.released)];
  // Per-company recent lists so a test can prove which companyId was queried.
  static final recentByCompany = <String, List<FundRequest>>{
    'c1': companyRecent,
    'cA': [_req('ra', 'cA', RequestStatus.released)],
    'cB': [_req('rb', 'cB', RequestStatus.acknowledged)],
  };

  @override
  Stream<List<FundRequest>> watchByStatus(String companyId, RequestStatus status) =>
      Stream.value(companyPending);
  @override
  Stream<List<FundRequest>> watchByStatusAll(RequestStatus status) =>
      Stream.value(allPending);
  @override
  Stream<List<FundRequest>> watchRecentByCompany(String companyId, int limit) =>
      Stream.value(recentByCompany[companyId] ?? const <FundRequest>[]);
  @override
  Stream<List<FundRequest>> watchRecentAll(int limit) => Stream.value(allRecent);

  @override
  Stream<List<FundRequest>> watchReleasedByCompany(String companyId) =>
      const Stream.empty();
  @override
  Stream<List<FundRequest>> watchReleasedAll(int limit) => const Stream.empty();
  @override
  Stream<List<FundRequest>> watchConflicts(String companyId) =>
      const Stream.empty();
  @override
  Stream<List<FundRequest>> watchPostReleaseReview(String companyId) =>
      const Stream.empty();
  @override
  Stream<List<FundRequest>> watchDisputed(String companyId) =>
      const Stream.empty();

  @override
  Stream<List<FundRequest>> watchAcknowledgedWorklist(String companyId) =>
      const Stream.empty();
  @override
  Stream<List<FundRequest>> watchApproverActedRecent(
          String companyId, int limit) =>
      const Stream.empty();
  @override
  Stream<List<FundRequest>> watchByFund(String companyId, String fundId) =>
      const Stream.empty();
  @override
  Future<Result<FundRequest>> getById(String id) async =>
      const Err(NotFoundFailure('not found'));
  @override
  Future<Result<String>> create(FundRequest request) async => const Ok('');
  @override
  Future<Result<void>> release({
    required FundRequest request,
    required String actorUid,
    required String releaseProofUrl,
    required String releaseSignatureUrl,
    required String clientReleaseId,
  }) async => const Ok(null);
  @override
  Future<Result<void>> captureLocalRelease({
    required FundRequest request,
    required String clientReleaseId,
    required String actorUid,
  }) async => const Ok(null);
  @override
  Future<Result<ReleaseSyncResult>> confirmPendingRelease({
    required FundRequest request,
    required String clientReleaseId,
    required String releaseProofUrl,
    required String releaseSignatureUrl,
    required String actorUid,
  }) async => const Ok(ReleaseSyncResult.confirmed);
  @override
  Future<Result<void>> backfillCreateImage({
    required String requestId,
    required String proofImageUrl,
  }) async => const Ok(null);
  @override
  Future<Result<void>> acknowledgePostRelease({
    required FundRequest request,
    required String actorUid,
    String? actorName,
    String? fundName,
  }) async => const Ok(null);
  @override
  Future<Result<void>> dispute({
    required FundRequest request,
    required String actorUid,
    required String reason,
    String? actorName,
    String? fundName,
  }) async => const Ok(null);
  @override
  Future<Result<void>> resolveConflict({
    required FundRequest request,
    required RequestStatus to,
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
  Stream<List<Replenishment>> watchByCompanyAndStatusRecent(
          String companyId, String status, int limit) =>
      const Stream.empty();

  @override
  Stream<List<Replenishment>> watchByFund(String companyId, String fundId) =>
      const Stream.empty();
  @override
  Future<Result<Replenishment>> createDraft(
          {required String fundId,
          required List<ReplenishmentItem> items,
          required String createdByUid}) async =>
      const Err(ValidationFailure('unused'));
  @override
  Future<Result<void>> createAndSubmit(
          {required String fundId,
          required List<ReplenishmentItem> items,
          required String actorUid,
          required String notes,
          String? submitterName,
          String? fundName,
          int? fundAvailableBalanceCentavos,
          int? originalAmountCentavos}) async =>
      const Ok(null);
  @override
  Future<Result<void>> submit(
          {required Replenishment replenishment,
          required String actorUid,
          required String notes,
          String? submitterName,
          String? fundName,
          int? fundAvailableBalanceCentavos,
          int? originalAmountCentavos}) async =>
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
  @override
  Future<Result<Replenishment>> getById(String id) async =>
      const Err(NotFoundFailure('unused'));
}

AppUser _user(
  UserRole role,
  String companyId, {
  List<String> memberships = const [],
}) =>
    AppUser(
      uid: 'u',
      companyId: companyId,
      companyIds: memberships,
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

  // --- Company picker drives the dashboard (multi-company non-admin) ---------

  test(
      'multi-company incharge: dashboard funds follow the picker (B), and flip '
      'back to A when the picker flips', () async {
    final c = container(
      _user(UserRole.incharge, 'cA', memberships: const ['cA', 'cB']),
    );
    c.listen(dashboardFundsProvider, (_, _) {});
    await c.read(currentUserProvider.future);

    // Picker on B => B's funds.
    c.read(adminActiveCompanyProvider.notifier).state = 'cB';
    await c.read(companyFundsProvider('cB').future);
    expect(c.read(dashboardFundsProvider).value, _FakeFundRepo.byCompany['cB']);

    // Flip the picker to A => A's funds.
    c.read(adminActiveCompanyProvider.notifier).state = 'cA';
    await c.read(companyFundsProvider('cA').future);
    expect(c.read(dashboardFundsProvider).value, _FakeFundRepo.byCompany['cA']);
  });

  test(
      'multi-company incharge: recent requests stream is scoped to the picked '
      'company (B), and flips with the picker', () async {
    final c = container(
      _user(UserRole.incharge, 'cA', memberships: const ['cA', 'cB']),
    );
    c.listen(recentRequestsProvider, (_, _) {});
    await c.read(currentUserProvider.future);

    c.read(adminActiveCompanyProvider.notifier).state = 'cB';
    await c.read(recentRequestsProvider.future);
    expect(c.read(recentRequestsProvider).value,
        _FakeRequestRepo.recentByCompany['cB']);

    c.read(adminActiveCompanyProvider.notifier).state = 'cA';
    await c.read(recentRequestsProvider.future);
    expect(c.read(recentRequestsProvider).value,
        _FakeRequestRepo.recentByCompany['cA']);
  });

  test(
      'multi-company incharge: with no picker selection, dashboard defaults to '
      'the first membership', () async {
    final c = container(
      _user(UserRole.incharge, 'cA', memberships: const ['cA', 'cB']),
    );
    c.listen(dashboardFundsProvider, (_, _) {});
    await c.read(currentUserProvider.future);
    // adminActiveCompanyProvider is null => effectiveCompanyId => first
    // membership (cA).
    await c.read(companyFundsProvider('cA').future);
    expect(c.read(dashboardFundsProvider).value, _FakeFundRepo.byCompany['cA']);
  });

  test('admin dashboard funds ignore the company picker (stay watchAll)',
      () async {
    final c = container(_user(UserRole.admin, ''));
    c.listen(dashboardFundsProvider, (_, _) {});
    await c.read(currentUserProvider.future);
    // Even with a picker selection, an admin's funds aggregate across all.
    c.read(adminActiveCompanyProvider.notifier).state = 'cB';
    await c.read(allFundsProvider.future);
    expect(c.read(dashboardFundsProvider).value, _FakeFundRepo.all);
  });

  test(
      'single-company non-admin: dashboard resolves to their sole membership, '
      'ignoring a stray picker value', () async {
    final c = container(_user(UserRole.incharge, 'c1'));
    c.listen(dashboardFundsProvider, (_, _) {});
    await c.read(currentUserProvider.future);
    // A stray session value must never leak into a single-company user's scope.
    c.read(adminActiveCompanyProvider.notifier).state = 'cB';
    await c.read(companyFundsProvider('c1').future);
    expect(c.read(dashboardFundsProvider).value, _FakeFundRepo.company);
  });
}
