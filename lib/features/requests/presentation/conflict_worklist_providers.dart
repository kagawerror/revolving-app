import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_active_company.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../domain/fund_request.dart';
import 'request_providers.dart';

/// The incharge "Conflicts" queue: requests in `conflict` status — offline
/// releases that overdrew the fund when they reached the server on sync. Maps to
/// `RequestRepository.watchConflicts(companyId)`, newest-first.
///
/// Resolves the operating company exactly like the approver inbox providers: an
/// admin operates a chosen company; everyone else is pinned to their own. Emits
/// an empty stream while signed out or before a company is chosen.
final conflictsProvider =
    StreamProvider.autoDispose<List<FundRequest>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  final companyId =
      effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));
  if (companyId.isEmpty) return const Stream.empty();
  return ref.watch(requestRepositoryProvider).watchConflicts(companyId);
});

/// The approver post-release review queue: `released` requests not yet
/// acknowledged/disputed. Maps to
/// `RequestRepository.watchPostReleaseReview(companyId)`.
///
/// NOTE: `pendingRequestsProvider` in `approver_inbox_providers.dart` already
/// watches `watchByStatus(companyId, released)`, which is the same set. This
/// alias exists so the new post-release-review screen reads from an explicitly
/// named provider; Phase 6 may collapse the two if it prefers a single source.
final postReleaseReviewProvider =
    StreamProvider.autoDispose<List<FundRequest>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  final companyId =
      effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));
  if (companyId.isEmpty) return const Stream.empty();
  return ref.watch(requestRepositoryProvider).watchPostReleaseReview(companyId);
});

/// Disputed releases for the operating company. Maps to
/// `RequestRepository.watchDisputed(companyId)`. Powers the "Disputed" follow-up
/// list (a small read-only section/tab the approver and incharge can revisit).
final disputedProvider =
    StreamProvider.autoDispose<List<FundRequest>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  final companyId =
      effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));
  if (companyId.isEmpty) return const Stream.empty();
  return ref.watch(requestRepositoryProvider).watchDisputed(companyId);
});
