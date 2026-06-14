import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';
import 'package:rev_app/features/reports/domain/report_models.dart';
import 'package:rev_app/features/reports/domain/report_period.dart';
import 'package:rev_app/features/reports/domain/report_repository.dart';
import 'package:rev_app/features/reports/presentation/report_providers.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

class _FakeReportRepo implements ReportRepository {
  _FakeReportRepo({this.released = const [], this.replenishments = const []});
  final List<FundRequest> released;
  final List<Replenishment> replenishments;
  Result<ReportPage<FundRequest>>? releasedOverride;

  @override
  Future<Result<ReportPage<FundRequest>>> fetchReleasedForReport(
          String companyId, DateRange window) async =>
      releasedOverride ?? Ok(ReportPage(released));

  @override
  Future<Result<ReportPage<Replenishment>>> fetchApprovedReplenishments(
          String companyId, DateRange window) async =>
      Ok(ReportPage(replenishments));

  @override
  Future<Result<ReportPage<ReplenishedLineRow>>> fetchReplenishmentLineItems(
    String companyId,
    DateRange window,
  ) async =>
      Ok(ReportPage<ReplenishedLineRow>(const []));
}

AppUser _user(UserRole role, String companyId) => AppUser(
      uid: 'u1',
      companyId: companyId,
      companyIds: [companyId],
      role: role,
      displayName: 'Test',
      email: 't@e.com',
    );

FundRequest _req(String id, int centavos, DateTime releasedAt) => FundRequest(
      id: id,
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: 'Jane',
      amount: Money.fromCentavos(centavos),
      purpose: 'Fuel',
      proofImageUrl: '',
      status: RequestStatus.released,
      releasedAt: releasedAt,
    );

ProviderContainer _container(AppUser user, _FakeReportRepo repo) {
  final c = ProviderContainer(overrides: [
    currentUserProvider.overrideWith((ref) => Stream.value(user)),
    reportRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('incharge: releasedReportProvider maps repo rows + grand total',
      () async {
    final repo = _FakeReportRepo(released: [
      _req('a', 10000, DateTime.now()),
      _req('b', 25000, DateTime.now()),
    ]);
    final c = _container(_user(UserRole.incharge, 'c1'), repo);
    // Let the auth stream resolve so reportCompanyIdProvider sees the user.
    await c.read(currentUserProvider.future);
    // Pin a period whose window contains the releases (now).
    c.read(reportPeriodProvider.notifier).setGranularity(PeriodGranularity.year);

    final summary = await c.read(releasedReportProvider.future);
    expect(summary.rows.length, 2);
    expect(summary.grandTotal, Money.fromCentavos(35000));
  });

  test('incharge: replenishmentReportProvider maps approved rows', () async {
    final repo = _FakeReportRepo(replenishments: [
      Replenishment(
        id: 'p1',
        companyId: 'c1',
        fundId: 'f1',
        status: ReplenishmentStatus.approved,
        requestIds: const ['a', 'b'],
        total: Money.fromCentavos(50000),
        reportNotes: '',
        createdByUid: 'u1',
        decidedAt: DateTime.now(),
      ),
    ]);
    final c = _container(_user(UserRole.incharge, 'c1'), repo);
    await c.read(currentUserProvider.future);
    c.read(reportPeriodProvider.notifier).setGranularity(PeriodGranularity.year);

    final summary = await c.read(replenishmentReportProvider.future);
    expect(summary.rows.single.itemCount, 2);
    expect(summary.grandTotal, Money.fromCentavos(50000));
  });

  test('truncated page surfaces as ReportSummary.truncated', () async {
    final repo = _FakeReportRepo()
      ..releasedOverride =
          Ok(ReportPage([_req('a', 10000, DateTime.now())], truncated: true));
    final c = _container(_user(UserRole.incharge, 'c1'), repo);
    await c.read(currentUserProvider.future);
    c.read(reportPeriodProvider.notifier).setGranularity(PeriodGranularity.year);

    final summary = await c.read(releasedReportProvider.future);
    expect(summary.truncated, isTrue);
  });

  test('admin (no active company) yields an empty summary, no repo scan',
      () async {
    final repo = _FakeReportRepo(released: [_req('a', 10000, DateTime.now())]);
    final c = _container(_user(UserRole.admin, ''), repo);
    final summary = await c.read(releasedReportProvider.future);
    expect(summary.rows, isEmpty);
    expect(summary.grandTotal, Money.zero);
  });

  test('repository Err surfaces as a provider error (Failure)', () async {
    final repo = _FakeReportRepo()
      ..releasedOverride = const Err(UnexpectedFailure('boom'));
    final c = _container(_user(UserRole.incharge, 'c1'), repo);
    await c.read(currentUserProvider.future);
    c.read(reportPeriodProvider.notifier).setGranularity(PeriodGranularity.year);

    await expectLater(
      c.read(releasedReportProvider.future),
      throwsA(isA<Failure>()),
    );
  });

  test('next() never steps past the current period', () {
    final c = _container(_user(UserRole.incharge, 'c1'), _FakeReportRepo());
    final notifier = c.read(reportPeriodProvider.notifier);
    notifier.setGranularity(PeriodGranularity.month);
    final before = c.read(reportPeriodProvider);
    notifier.next(); // already current -> no-op
    expect(c.read(reportPeriodProvider), before);
    expect(c.read(isAtCurrentPeriodProvider), isTrue);
    // Stepping back then forward returns to current.
    notifier.prev();
    expect(c.read(isAtCurrentPeriodProvider), isFalse);
    notifier.next();
    expect(c.read(isAtCurrentPeriodProvider), isTrue);
  });
}
