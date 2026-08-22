import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_providers.dart';
import '../domain/visible_funds.dart';

/// The funds the *current* incharge custodian may operate on, resolved from the
/// company-scoped fund stream the incharge home already uses, then narrowed by
/// the user's per-fund assignment via [resolveVisibleFunds].
///
/// Sourcing:
///   * **non-admin** (the incharge): the funds of their effective company
///     (`companyFundsProvider(companyId)`), then assignment-scoped. An empty
///     assignment yields the strict empty state (`isEmptyState`).
///   * **admin superuser**: the funds of the chosen company, returned unchanged
///     (`isAssignmentScoped == false`) — admins are not fund-scoped, matching
///     `resolveVisibleFunds`'s contract.
///
/// Companyless admin (no company picked yet) is handled by the home BEFORE this
/// provider is read, so [companyId] is always non-empty here. The provider is a
/// UI filter only — it never issues a `whereIn` query and adds no index.
final inchargeVisibleFundsProvider =
    Provider.autoDispose.family<AsyncValue<VisibleFunds>, String>(
  (ref, companyId) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) return const AsyncValue.loading();
    final funds = ref.watch(companyFundsProvider(companyId));
    return funds.whenData((list) => resolveVisibleFunds(user, list));
  },
);
