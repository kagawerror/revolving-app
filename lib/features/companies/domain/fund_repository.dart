import '../../../core/error/result.dart';
import '../../../core/money/money.dart';
import 'fund.dart';

abstract interface class FundRepository {
  Stream<List<Fund>> watchByCompany(String companyId);
  Stream<List<Fund>> watchAll();
  Stream<Fund?> watchById(String fundId);
  Future<Result<void>> create(Fund fund);

  /// Updates non-money fund metadata (name + low-balance threshold). CODER:
  /// implement in the Firestore repo; this never touches balance/budget.
  Future<Result<void>> updateDetails({
    required String fundId,
    required String name,
    required int lowBalanceThresholdPct,
  });

  /// Re-sets the original budget to [newBudget], applying the SAME signed delta
  /// to the available balance, inside a transaction, with an audit `history`
  /// entry (mirrors `release`). CODER: implement in the Firestore repo and the
  /// matching firestore.rules block.
  Future<Result<void>> adjustBudget({
    required String fundId,
    required Money newBudget,
    required String actorUid,
    required String note,
  });
}
