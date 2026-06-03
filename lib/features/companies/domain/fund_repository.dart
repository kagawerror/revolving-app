import 'fund.dart';

abstract interface class FundRepository {
  Stream<List<Fund>> watchByCompany(String companyId);
  Stream<Fund?> watchById(String fundId);
  Future<void> create(Fund fund);
}
