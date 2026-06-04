import '../../../core/error/result.dart';
import 'fund_request.dart';
import 'request_status.dart';

abstract interface class RequestRepository {
  Stream<List<FundRequest>> watchByFund(String fundId);
  Stream<List<FundRequest>> watchByStatus(String companyId, RequestStatus status);
  Stream<List<FundRequest>> watchRecentByCompany(String companyId, int limit);

  /// Admin-only: every company's requests with the given status (unscoped).
  Stream<List<FundRequest>> watchByStatusAll(RequestStatus status);

  /// Admin-only: most-recent requests across every company (unscoped).
  Stream<List<FundRequest>> watchRecentAll(int limit);

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
