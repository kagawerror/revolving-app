import '../../../core/error/result.dart';
import '../../requests/domain/fund_request.dart';
import 'fund_audit.dart';

abstract class FundAuditRepository {
  /// Writes a new immutable audit; returns the new document id.
  Future<Result<String>> create(FundAudit audit);

  /// Released-but-not-yet-replenished requests for the fund, used to compute the
  /// outstanding cash that should be deducted from the expected on-hand balance.
  Future<Result<List<FundRequest>>> fetchOutstandingForFund(
    String companyId,
    String fundId,
  );

  Future<Result<FundAudit>> getById(String id);

  /// Audits for a fund, newest first.
  Stream<List<FundAudit>> watchByFund(String companyId, String fundId);
}
