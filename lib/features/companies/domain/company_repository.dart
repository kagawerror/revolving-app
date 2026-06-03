import 'company.dart';

abstract interface class CompanyRepository {
  Stream<List<Company>> watchAll();
  Future<String> create(String name);
}
