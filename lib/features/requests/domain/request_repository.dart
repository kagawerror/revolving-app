import '../../../core/error/result.dart';
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

  /// Admin-only: released requests across every company, newest-first, capped
  /// at [limit] — the source for the grouped admin aging view.
  Stream<List<FundRequest>> watchReleasedAll(int limit);

  Future<Result<String>> create(FundRequest request);

  /// Generic status move that also appends a history event. Used for
  /// pendingAck, acknowledged, rejected, readyForRelease.
  Future<Result<void>> transition({
    required FundRequest request,
    required RequestStatus to,
    required String actorUid,
    String? note,
  });

  /// RELEASE: atomically validates balance, deducts, flips fund to `low` if
  /// the new balance is at/under threshold, sets request to released, logs history.
  Future<Result<void>> release({
    required FundRequest request,
    required String actorUid,
  });
}
