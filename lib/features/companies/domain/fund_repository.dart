import '../../../core/error/result.dart';
import 'fund.dart';

abstract interface class FundRepository {
  Stream<List<Fund>> watchByCompany(String companyId);
  Stream<List<Fund>> watchAll();
  Stream<Fund?> watchById(String fundId);
  Future<Result<void>> create(Fund fund);
}
