import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/company.dart';
import '../../companies/domain/fund.dart';
import '../../companies/presentation/admin_active_company.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../../companies/presentation/admin_providers.dart';
import '../../replenishment/domain/replenishment.dart';
import '../../replenishment/presentation/replenishment_providers.dart';
import '../../requests/domain/fund_request.dart';
import '../../requests/presentation/approver_inbox_providers.dart';
import '../../requests/presentation/request_providers.dart';
import '../domain/dashboard_summary.dart';

/// The company whose data the dashboard renders. Company-scoped roles honor the
/// in-session company picker via [effectiveCompanyId]; admins resolve to '' and
/// stay on their cross-company ("all") queries below.
final dashboardCompanyIdProvider = Provider<String>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return '';
  return effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));
});

/// Funds feeding the dashboard, scoped by role. Admins belong to no company
/// (`companyId == ''`), so a company-scoped query would always be empty — they
/// instead see every company's funds. Company-scoped roles see the company
/// currently selected in the picker (their sole membership when single-company),
/// resolved via [dashboardCompanyIdProvider].
final dashboardFundsProvider =
    Provider.autoDispose<AsyncValue<List<Fund>>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const AsyncValue.loading();
  final companyId = ref.watch(dashboardCompanyIdProvider);
  return user.role.isAdmin
      ? ref.watch(allFundsProvider)
      : ref.watch(companyFundsProvider(companyId));
});

/// Pending-ack requests feeding the dashboard, scoped by role. Admins see every
/// company's pending requests; company-scoped roles see only their own. Mirrors
/// [dashboardFundsProvider]. Distinct from the shared [pendingRequestsProvider],
/// which stays company-scoped for the approver inbox/home screens.
final dashboardPendingRequestsProvider =
    Provider.autoDispose<AsyncValue<List<FundRequest>>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const AsyncValue.loading();
  return user.role.isAdmin
      ? ref.watch(allPendingRequestsProvider)
      : ref.watch(pendingRequestsProvider);
});

/// Submitted replenishments feeding the dashboard, scoped by role. See
/// [dashboardPendingRequestsProvider] for the admin-vs-company rationale.
final dashboardPendingReplenishmentsProvider =
    Provider.autoDispose<AsyncValue<List<Replenishment>>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const AsyncValue.loading();
  return user.role.isAdmin
      ? ref.watch(allPendingReplenishmentsProvider)
      : ref.watch(pendingReplenishmentsProvider);
});

final recentRequestsProvider =
    StreamProvider.autoDispose<List<FundRequest>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const <FundRequest>[]);
  final repo = ref.watch(requestRepositoryProvider);
  final companyId = ref.watch(dashboardCompanyIdProvider);
  return user.role.isAdmin
      ? repo.watchRecentAll(15)
      : repo.watchRecentByCompany(companyId, 15);
});

/// Map of companyId -> company name, for labeling fund cards. Sourced from the
/// already-streamed [companiesProvider]; resolves to an empty map while
/// companies are still loading (the dashboard renders funds without the company
/// line rather than blocking the list).
final companyNamesProvider = Provider.autoDispose<Map<String, String>>((ref) {
  final companies =
      ref.watch(companiesProvider).valueOrNull ?? const <Company>[];
  return {for (final c in companies) c.id: c.name};
});

final dashboardSummaryProvider =
    Provider.autoDispose<AsyncValue<DashboardSummary>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const AsyncValue.loading();
  final funds = ref.watch(dashboardFundsProvider);
  final pendingReq =
      ref.watch(dashboardPendingRequestsProvider).valueOrNull?.length ?? 0;
  final pendingRepl =
      ref.watch(dashboardPendingReplenishmentsProvider).valueOrNull?.length ?? 0;
  return funds.whenData((list) => DashboardSummary(
        totals: computeFundTotals(list),
        pendingRequestCount: pendingReq,
        pendingReplenishmentCount: pendingRepl,
      ));
});
