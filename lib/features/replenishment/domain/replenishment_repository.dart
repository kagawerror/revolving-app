import '../../../core/error/result.dart';
import 'replenishment.dart';

abstract interface class ReplenishmentRepository {
  Stream<List<Replenishment>> watchByFund(String fundId);
  Stream<List<Replenishment>> watchByCompanyAndStatus(String companyId, String status);

  /// Compiles released-unreplenished requests for the fund into a DRAFT and flips
  /// the fund to `replenishing`. Fails if the fund is already replenishing or has
  /// no released-unreplenished requests.
  Future<Result<Replenishment>> createDraft({required String fundId, required String createdByUid});

  Future<Result<void>> submit({required Replenishment replenishment, required String actorUid, required String notes});

  /// Atomic: tag requests replenished, reset fund balance to original ceiling, fund→active.
  Future<Result<void>> approve({required Replenishment replenishment, required String actorUid});

  Future<Result<void>> reject({required Replenishment replenishment, required String actorUid});

  /// Cancels a draft and returns the fund to active/low.
  Future<Result<void>> discardDraft({required Replenishment replenishment});
}
