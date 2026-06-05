import '../../../core/error/result.dart';
import 'replenishment.dart';

abstract interface class ReplenishmentRepository {
  /// Replenishments for one fund, scoped to its company. companyId is required
  /// (not just fundId) so the list is provably company-scoped for the
  /// sameCompany read rule — Firestore rejects an unscoped query otherwise.
  Stream<List<Replenishment>> watchByFund(String companyId, String fundId);
  Stream<List<Replenishment>> watchByCompanyAndStatus(String companyId, String status);

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

  Future<Result<void>> submit({required Replenishment replenishment, required String actorUid, required String notes});

  /// One-tap selection→submit for the incharge popup: creates the draft from
  /// [items], then submits it for approval. Rolls the draft back (so the fund is
  /// not left locked in `replenishing`) if the submit step fails.
  Future<Result<void>> createAndSubmit({
    required String fundId,
    required List<ReplenishmentItem> items,
    required String actorUid,
    required String notes,
  });

  /// Atomic: tag the bundled requests `replenished`, ADD their total back to the
  /// fund balance, and set fund status from the new balance (active/low).
  Future<Result<void>> approve({required Replenishment replenishment, required String actorUid});

  Future<Result<void>> reject({required Replenishment replenishment, required String actorUid});

  /// Cancels a draft and returns the fund to active/low.
  Future<Result<void>> discardDraft({required Replenishment replenishment});
}
