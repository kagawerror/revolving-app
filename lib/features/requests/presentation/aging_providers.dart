import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_active_company.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../../companies/presentation/admin_providers.dart';
import '../domain/aging.dart';
import '../domain/fund_request.dart';
import 'request_providers.dart';

/// Cap on the admin cross-company outstanding feed. The view groups by company
/// client-side, so this bounds the live listener rather than paginating.
const kAgingAdminLimit = 200;

/// Incharge aging list: this effective company's outstanding requests, newest
/// first. Resolves the company exactly like the other inbox providers — admin
/// operates a chosen company; everyone else is pinned to their own.
final agingRequestsProvider =
    StreamProvider.autoDispose<List<FundRequest>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  final companyId =
      effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));
  if (companyId.isEmpty) return const Stream.empty();
  return ref
      .watch(requestRepositoryProvider)
      .watchOutstandingByCompany(companyId);
});

/// Admin-only source: outstanding requests across every company, newest first,
/// capped at [kAgingAdminLimit]. Grouped client-side by [agingGroupedProvider].
final allOutstandingRequestsProvider =
    StreamProvider.autoDispose<List<FundRequest>>(
        (ref) => ref.watch(requestRepositoryProvider).watchOutstandingAll(kAgingAdminLimit));

/// Admin grouped aging view: folds the cross-company outstanding feed and the
/// company list into per-company [AgingGroup]s. Both upstreams are async, so we
/// surface loading/error from whichever isn't ready yet and only compute the
/// grouping once both have data.
final agingGroupedProvider =
    Provider.autoDispose<AsyncValue<List<AgingGroup>>>((ref) {
  final companies = ref.watch(companiesProvider);
  final outstanding = ref.watch(allOutstandingRequestsProvider);

  return companies.when(
    loading: () => const AsyncValue.loading(),
    error: AsyncValue.error,
    data: (companyList) => outstanding.when(
      loading: () => const AsyncValue.loading(),
      error: AsyncValue.error,
      data: (outstandingList) =>
          AsyncValue.data(groupOutstandingByCompany(companyList, outstandingList)),
    ),
  );
});
