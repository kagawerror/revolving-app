import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_active_company.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'request_providers.dart';

final pendingRequestsProvider = StreamProvider<List<FundRequest>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  // Admin operates a chosen company; everyone else is pinned to their own.
  final companyId =
      effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));
  if (companyId.isEmpty) return const Stream.empty();
  return ref
      .watch(requestRepositoryProvider)
      .watchByStatus(companyId, RequestStatus.pendingAck);
});

/// The incharge release worklist: acknowledged + readyForRelease requests for
/// the effective company. Released items drop off automatically (filter-only).
/// Resolves the company exactly like [pendingRequestsProvider].
final acknowledgedWorklistProvider = StreamProvider<List<FundRequest>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  final companyId =
      effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));
  if (companyId.isEmpty) return const Stream.empty();
  return ref
      .watch(requestRepositoryProvider)
      .watchAcknowledgedWorklist(companyId);
});

/// Admin-only: pending-ack requests across every company.
final allPendingRequestsProvider = StreamProvider<List<FundRequest>>((ref) =>
    ref.watch(requestRepositoryProvider).watchByStatusAll(RequestStatus.pendingAck));
