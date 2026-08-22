import '../../../core/error/result.dart';
import 'company.dart';

abstract interface class CompanyRepository {
  Stream<List<Company>> watchAll();
  Future<Result<String>> create(String name);

  /// Single-doc fetch by id. Used to denormalize a company name at notification
  /// write time. Missing → [NotFoundFailure]; failure → [UnexpectedFailure].
  Future<Result<Company>> getById(String id);

  /// Renames an existing company. CODER: implement in the Firestore repo.
  Future<Result<void>> update(String id, String name);
}
