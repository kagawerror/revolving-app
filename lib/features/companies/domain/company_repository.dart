import '../../../core/error/result.dart';
import 'company.dart';

abstract interface class CompanyRepository {
  Stream<List<Company>> watchAll();
  Future<Result<String>> create(String name);
}
