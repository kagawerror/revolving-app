import '../../../core/error/result.dart';
import '../../sync/domain/release_sync_result.dart';
import 'fund_request.dart';
import 'request_status.dart';

abstract interface class RequestRepository {
  /// Requests for one fund, scoped to its company. The companyId is required
  /// (not just fundId) so the query is provably company-scoped for the
  /// sameCompany read rule — Firestore rejects an unscoped list otherwise.
  Stream<List<FundRequest>> watchByFund(String companyId, String fundId);
  Stream<List<FundRequest>> watchByStatus(String companyId, RequestStatus status);
  Stream<List<FundRequest>> watchRecentByCompany(String companyId, int limit);

  /// Yields the company's requests with status `acknowledged` or
  /// `readyForRelease` (the incharge release worklist), most-recent first.
  /// Released items drop off automatically since the query filters by status.
  Stream<List<FundRequest>> watchAcknowledgedWorklist(String companyId);

  /// The approver "Approved" tab revisit list: the company's requests that have
  /// been acted on (`acknowledged` / `readyForRelease` / `released`),
  /// newest-first, capped at [limit]. Read-only — no inline actions.
  Stream<List<FundRequest>> watchApproverActedRecent(String companyId, int limit);

  /// Admin-only: every company's requests with the given status (unscoped).
  Stream<List<FundRequest>> watchByStatusAll(RequestStatus status);

  /// Admin-only: most-recent requests across every company (unscoped).
  Stream<List<FundRequest>> watchRecentAll(int limit);

  /// Released requests for one company, newest-first — the incharge aging list.
  Stream<List<FundRequest>> watchReleasedByCompany(String companyId);

  /// Overdraft conflicts for one company (status == conflict), newest-first —
  /// the incharge resolution queue.
  Stream<List<FundRequest>> watchConflicts(String companyId);

  /// Post-release approver review list for one company (status == released),
  /// newest-first — items awaiting acknowledge/dispute.
  Stream<List<FundRequest>> watchPostReleaseReview(String companyId);

  /// Disputed releases for one company (status == disputed), newest-first.
  Stream<List<FundRequest>> watchDisputed(String companyId);

  /// Admin-only: released requests across every company, newest-first, capped
  /// at [limit] — the source for the grouped admin aging view.
  Stream<List<FundRequest>> watchReleasedAll(int limit);

  /// Single-doc fetch by id (for the alert tap-to-open flow). Missing →
  /// [NotFoundFailure]; failure → [UnexpectedFailure].
  Future<Result<FundRequest>> getById(String id);

  Future<Result<String>> create(FundRequest request);

  /// RELEASE: atomically validates balance, deducts, flips fund to `low` if
  /// the new balance is at/under threshold, sets request to released, logs
  /// history. Requires a release proof photo and recipient signature (both
  /// pre-uploaded URLs, mandatory) which are written into the request doc
  /// atomically and are immutable thereafter.
  ///
  /// [clientReleaseId] is a stable on-device id persisted into the request doc
  /// and the release history event so a later offline replay can be deduped
  /// idempotently (online path still uses a runTransaction as before).
  Future<Result<void>> release({
    required FundRequest request,
    required String actorUid,
    required String releaseProofUrl,
    required String releaseSignatureUrl,
    required String clientReleaseId,
  });

  /// OFFLINE CAPTURE of a release. A PLAIN update (NOT a transaction —
  /// transactions require a server round-trip and fail offline) that flips a
  /// `created` request to `released` with `releaseState='localPending'`, stamps
  /// the [clientReleaseId] for idempotent Phase-5 replay, and appends a history
  /// event. The release proof + signature URLs are left empty (the images are
  /// stored locally and uploaded + backfilled on sync).
  ///
  /// MONEY SAFETY: this NEVER touches the fund balance. The server-side release
  /// transaction (online release / Phase-5 replay) is the single place the fund
  /// is debited — exactly once — so the optimistic UI balance (which already
  /// subtracts pending release intents) is the only local reflection of this.
  /// Debiting here would double-deduct.
  Future<Result<void>> captureLocalRelease({
    required FundRequest request,
    required String clientReleaseId,
    required String actorUid,
  });

  /// POST-HOC ACKNOWLEDGE: an approver acknowledges an already-released spend
  /// (`released → acknowledged`). Plain update, NO money movement; appends a
  /// history event.
  /// [actorName]/[fundName] are optional display values denormalized onto the
  /// `requestAcknowledged` notification for the incharge's alert list. They
  /// never affect money or the transition.
  Future<Result<void>> acknowledgePostRelease({
    required FundRequest request,
    required String actorUid,
    String? actorName,
    String? fundName,
  });

  /// DISPUTE: an approver flags a released/acknowledged spend
  /// (`released | acknowledged → disputed`). Records the reason + actor; NO
  /// balance change. Disputed cash is still reconcilable via replenishment.
  /// [actorName]/[fundName] are optional display values denormalized onto the
  /// `requestDisputed` notification. The dispute [reason] is NEVER put in the
  /// notification body (PII) — it stays on the detail screen.
  Future<Result<void>> dispute({
    required FundRequest request,
    required String actorUid,
    required String reason,
    String? actorName,
    String? fundName,
  });

  /// REPLAY of a captured offline release (Phase 5 sync engine). Inside a
  /// `runTransaction`, re-reads the request doc — its own idempotency ledger:
  ///
  ///  - `releaseState == 'serverConfirmed'` → a prior replay already debited the
  ///    fund; returns [ReleaseSyncResult.alreadyConfirmed] with NO second debit
  ///    (backfilling URLs/clearing pendingImageRef only if still empty).
  ///  - `releaseState == 'conflict'` → returns [ReleaseSyncResult.conflict]
  ///    idempotently, no fund touch.
  ///  - else → re-reads the CURRENT server fund and reconciles via
  ///    `reconcileRelease`: if the fund can cover it, debits EXACTLY ONCE, sets
  ///    `releaseState='serverConfirmed'`, backfills the release URLs, clears
  ///    `pendingImageRef`, writes a `releaseConfirmed` history event with
  ///    [clientReleaseId], and returns [ReleaseSyncResult.confirmed]. If the
  ///    fund can no longer cover it (cross-device overdraft), sets the request
  ///    `status='conflict'`/`releaseState='conflict'`, writes a `conflict`
  ///    history event, does NOT debit, and returns [ReleaseSyncResult.conflict].
  ///
  /// The [releaseProofUrl]/[releaseSignatureUrl] are uploaded by the engine
  /// before this call. The fund is debited ONLY here (server-side, once).
  Future<Result<ReleaseSyncResult>> confirmPendingRelease({
    required FundRequest request,
    required String clientReleaseId,
    required String releaseProofUrl,
    required String releaseSignatureUrl,
    required String actorUid,
  });

  /// BACKFILL the proof image URL on an offline-created request once the engine
  /// has uploaded it. A plain guarded update: sets `proofImageUrl` and clears
  /// `pendingImageRef`; never moves money and never changes the amount/status.
  Future<Result<void>> backfillCreateImage({
    required String requestId,
    required String proofImageUrl,
  });

  /// RESOLVE CONFLICT: the incharge resolves an overdraft `conflict`. [to] must
  /// be [RequestStatus.released] (re-runs the release transaction so the money
  /// re-validates via computeRelease) or [RequestStatus.rejected] (plain
  /// update + history, no money).
  /// [fundName] is an optional display value denormalized onto the
  /// `requestRejected` notification (reject path only); it never affects money
  /// or the transition. The release path sources the fund name itself.
  Future<Result<void>> resolveConflict({
    required FundRequest request,
    required RequestStatus to,
    required String actorUid,
    String? fundName,
  });
}
