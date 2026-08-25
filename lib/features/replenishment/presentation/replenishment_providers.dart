import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../services/firebase/firebase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_active_company.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../../messaging/presentation/messaging_providers.dart';
import '../data/firestore_replenishment_repository.dart';
import '../domain/liquidation_history.dart';
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

/// Auto-approved reports for the company that an approver has not yet
/// acknowledged. Streams `approved` reports (reusing the existing
/// `(companyId, status)` index — NO new index/server filter) and post-filters
/// to those still needing acknowledgment.
final needsAckReplenishmentsProvider =
    StreamProvider.autoDispose<List<Replenishment>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  final companyId =
      effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));
  if (companyId.isEmpty) return const Stream.empty();
  return ref
      .watch(replenishmentRepositoryProvider)
      .watchByCompanyAndStatus(companyId, ReplenishmentStatus.approved.name)
      .map((reps) => reps.where((r) => r.needsAcknowledgment).toList());
});

/// The approver "to-act" list: legacy in-flight `submitted` reports UNION
/// auto-approved reports awaiting acknowledgment. Derived purely from the two
/// existing streams above — adds no Firestore read. Keeps the legacy submitted
/// drain available alongside the new acknowledge prompt.
final approverActionableReplenishmentsProvider =
    Provider.autoDispose<List<Replenishment>>((ref) {
  final submitted =
      ref.watch(pendingReplenishmentsProvider).valueOrNull ??
          const <Replenishment>[];
  final needsAck =
      ref.watch(needsAckReplenishmentsProvider).valueOrNull ??
          const <Replenishment>[];
  return [...submitted, ...needsAck];
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

/// Family key for [liquidationHistoryProvider]: the request's OWN companyId
/// (not `effectiveCompanyId`) plus its id.
typedef LiquidationHistoryArgs = ({String companyId, String requestId});

/// The itemized liquidation ledger of ONE request — every non-draft
/// replenishment report line that liquidated it, oldest-first. Feeds the full
/// (detail) breakdown variant, which replaces its two lumped partial rows with
/// one row per entry.
///
/// Keyed by the request document's own `companyId`: the request doc carries the
/// authoritative tenant, and scoping the query that way also lets an admin read
/// cross-company via the rules' `isAdmin()` short-circuit. autoDispose so the
/// listener closes with the detail screen/sheet.
///
/// A query failure here is invisible in the UI — the breakdown just degrades to
/// its lumped rows — so the stream leaves a `dart:developer` breadcrumb before
/// forwarding the error. The likeliest cause is a `FAILED_PRECONDITION` from the
/// `(companyId, requestIds array-contains)` composite index not being deployed
/// yet — see firestore.indexes.json (deliberately two fields, no `createdAt`, so
/// no `orderBy` here — see [FirestoreReplenishmentRepository.watchByRequestId]).
/// Only ids and the error are logged: no amounts, no PII.
final liquidationHistoryProvider = StreamProvider.autoDispose
    .family<List<LiquidationEntry>, LiquidationHistoryArgs>(
  (ref, arg) => ref
      .watch(replenishmentRepositoryProvider)
      .watchByRequestId(arg.companyId, arg.requestId)
      .map((reps) => computeLiquidationHistory(arg.requestId, reps))
      .handleError((Object e, StackTrace st) {
    developer.log(
      'liquidation history stream failed '
      '(companyId=${arg.companyId}, requestId=${arg.requestId})',
      name: 'replenishment',
      error: e,
      stackTrace: st,
    );
    // handleError swallows by default; re-throw so the provider still surfaces
    // AsyncError rather than hanging in AsyncLoading forever.
    Error.throwWithStackTrace(e, st);
  }),
);
