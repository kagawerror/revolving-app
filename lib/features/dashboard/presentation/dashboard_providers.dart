import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_providers.dart';
import '../../replenishment/presentation/replenishment_providers.dart';
import '../../requests/domain/fund_request.dart';
import '../../requests/presentation/approver_inbox_providers.dart';
import '../../requests/presentation/request_providers.dart';
import '../domain/dashboard_summary.dart';

final recentRequestsProvider = StreamProvider<List<FundRequest>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const <FundRequest>[]);
  return ref.watch(requestRepositoryProvider).watchRecentByCompany(user.companyId, 15);
});

final dashboardSummaryProvider = Provider<AsyncValue<DashboardSummary>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const AsyncValue.loading();
  final funds = ref.watch(companyFundsProvider(user.companyId));
  final pendingReq = ref.watch(pendingRequestsProvider).valueOrNull?.length ?? 0;
  final pendingRepl = ref.watch(pendingReplenishmentsProvider).valueOrNull?.length ?? 0;
  return funds.whenData((list) => DashboardSummary(
        totals: computeFundTotals(list),
        pendingRequestCount: pendingReq,
        pendingReplenishmentCount: pendingRepl,
      ));
});
