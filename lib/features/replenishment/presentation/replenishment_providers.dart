import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../services/firebase/firebase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_active_company.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../../messaging/presentation/messaging_providers.dart';
import '../data/firestore_replenishment_repository.dart';
import '../domain/pending_partials.dart';
import '../domain/replenishment.dart';
import '../domain/replenishment_repository.dart';
import '../domain/replenishment_status.dart';

final replenishmentRepositoryProvider = Provider<ReplenishmentRepository>(
    (ref) => FirestoreReplenishmentRepository(
        ref.watch(firestoreProvider), ref.watch(pushSenderProvider)));

/// Cap on the approver "Approved" tab revisit list — the most recent approved
/// replenishment reports, newest-first.
const kApprovedTabLimit = 25;

final pendingReplenishmentsProvider =
    StreamProvider.autoDispose<List<Replenishment>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  final companyId =
      effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));
  if (companyId.isEmpty) return const Stream.empty();
  return ref.watch(replenishmentRepositoryProvider)
      .watchByCompanyAndStatus(companyId, ReplenishmentStatus.submitted.name);
});

/// The approver "Approved" tab: this company's approved replenishment reports,
/// newest-first, capped. Resolves the company like [pendingReplenishmentsProvider].
final recentApprovedReplenishmentsProvider =
    StreamProvider.autoDispose<List<Replenishment>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  final companyId =
      effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));
  if (companyId.isEmpty) return const Stream.empty();
  return ref.watch(replenishmentRepositoryProvider).watchByCompanyAndStatusRecent(
      companyId, ReplenishmentStatus.approved.name, kApprovedTabLimit);
});

/// Admin-only: submitted replenishments across every company.
final allPendingReplenishmentsProvider =
    StreamProvider.autoDispose<List<Replenishment>>((ref) =>
        ref.watch(replenishmentRepositoryProvider)
            .watchByStatusAll(ReplenishmentStatus.submitted.name));

/// requestId → total submitted-but-not-yet-approved amount, summed across the
/// PARTIAL items of every submitted replenishment. Full items are excluded —
/// this figure feeds the request breakdown's "pending partial · for approval"
/// line, which is specifically about partial replenishments. Derived purely
/// from the existing [pendingReplenishmentsProvider] stream — adds no
/// Firestore read.
final pendingPartialByRequestProvider =
    Provider.autoDispose<Map<String, Money>>((ref) {
  final reps = ref.watch(pendingReplenishmentsProvider).valueOrNull ??
      const <Replenishment>[];
  return partialAmountByRequest(reps);
});
