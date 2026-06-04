import '../../../core/error/result.dart';
import 'company.dart';

abstract interface class CompanyRepository {
  Stream<List<Company>> watchAll();
  Future<Result<String>> create(String name);

  /// Renames an existing company. CODER: implement in the Firestore repo.
  Future<Result<void>> update(String id, String name);
}
