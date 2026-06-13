import '../../../core/error/result.dart';
import '../../../core/money/money.dart';
import '../../auth/domain/app_user.dart';
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

  /// Applies a signed [signedDeltaCentavos] to the available balance ONLY,
  /// inside a transaction that re-reads + re-validates against current server
  /// state (mirrors `adjustBudget`/`release`). The original budget and
  /// threshold are never touched; status is recomputed against the unchanged
  /// budget. A non-empty [reason] is required (enforced by the caller/UI) and
  /// recorded in the `history` audit entry — never logged. Only admin or CEO may
  /// call this (mirrored in firestore.rules). CODER: implement in the Firestore
  /// repo and the matching firestore.rules block.
  Future<Result<void>> adjustBalance({
    required String fundId,
    required int signedDeltaCentavos,
    required String reason,
    required String actorUid,
    required UserRole actorRole,
  });
}
