import '../../../core/error/result.dart';
import 'replenishment.dart';

abstract interface class ReplenishmentRepository {
  /// Replenishments for one fund, scoped to its company. companyId is required
  /// (not just fundId) so the list is provably company-scoped for the
  /// sameCompany read rule — Firestore rejects an unscoped query otherwise.
  Stream<List<Replenishment>> watchByFund(String companyId, String fundId);
  Stream<List<Replenishment>> watchByCompanyAndStatus(String companyId, String status);

  /// The approver "Approved" tab revisit list: a company's replenishments with
  /// the given [status] (e.g. `approved`), newest-first, capped at [limit].
  Stream<List<Replenishment>> watchByCompanyAndStatusRecent(
      String companyId, String status, int limit);

  /// Admin-only: every company's replenishments with the given status (unscoped).
  Stream<List<Replenishment>> watchByStatusAll(String status);

  /// Compiles the SELECTED released requests for the fund into a DRAFT report
  /// of line [items] (each Full or Partial) and flips the fund to `replenishing`.
  /// Full items' amounts are recomputed server-side from each request's
  /// remaining; partial items must satisfy 0 < amount < remaining and carry
  /// remarks. Fails if the fund is already replenishing, the selection is empty,
  /// or any item is invalid / no longer releasable.
  Future<Result<Replenishment>> createDraft({
    required String fundId,
    required List<ReplenishmentItem> items,
    required String createdByUid,
  });

  /// AUTO-APPROVE submit. The incharge's submit is now the money transaction:
  /// in one `runTransaction` it re-reads + re-validates the report and its line
  /// items, credits the fund (status restored active/low), tags the bundled
  /// requests, writes partial-audit rows, and lands the report directly in
  /// `approved` (`autoApproved: true`, `acknowledgedByUid: null`). No approver
  /// gate. After commit it notifies approvers `replenishmentNeedsAck`
  /// (unawaited). The optional display values are denormalized onto the report
  /// (`submittedByName`) and never affect money logic.
  Future<Result<void>> submit({
    required Replenishment replenishment,
    required String actorUid,
    required String notes,
    String? submitterName,
    String? fundName,
    int? fundAvailableBalanceCentavos,
    int? originalAmountCentavos,
  });

  /// One-tap selection→submit for the incharge popup: creates the draft from
  /// [items], then submits it for approval. Rolls the draft back (so the fund is
  /// not left locked in `replenishing`) if the submit step fails.
  Future<Result<void>> createAndSubmit({
    required String fundId,
    required List<ReplenishmentItem> items,
    required String actorUid,
    required String notes,
    String? submitterName,
    String? fundName,
    int? fundAvailableBalanceCentavos,
    int? originalAmountCentavos,
  });

  /// Acknowledges an auto-approved report. NOT a money transaction: the fund is
  /// already credited. Stamps `acknowledgedByUid`/`acknowledgedByName`/
  /// `acknowledgedAt` on the (already `approved`) doc, clearing its "Needs
  /// acknowledgment" badge — the STATUS is unchanged. Idempotent: a second call
  /// on an already-acknowledged report returns `Ok`. Errors if the report is
  /// not `approved`.
  Future<Result<void>> acknowledge({
    required Replenishment replenishment,
    required String actorUid,
    String? actorName,
  });

  /// LEGACY (in-flight `submitted` docs only). Atomic: tag the bundled requests
  /// `replenished`, ADD their total back to the fund balance, and set fund
  /// status from the new balance (active/low). The new submit path auto-approves
  /// instead — this remains only to drain reports submitted before that change.
  Future<Result<void>> approve({required Replenishment replenishment, required String actorUid});

  /// LEGACY (in-flight `submitted` docs only). REJECT a submitted report
  /// (`submitted → rejected`). Records the required
  /// [reason] + actor on the report and restores the fund status (no balance
  /// change). The rejection [reason] is NEVER put in the notification body
  /// (PII) — it stays on the report's detail screen.
  Future<Result<void>> reject({
    required Replenishment replenishment,
    required String actorUid,
    required String reason,
  });

  /// Cancels a draft and returns the fund to active/low.
  Future<Result<void>> discardDraft({required Replenishment replenishment});

  /// Single-doc fetch by id (for the approver tap-to-review flow). Missing →
  /// [NotFoundFailure]; failure → [UnexpectedFailure].
  Future<Result<Replenishment>> getById(String id);
}
