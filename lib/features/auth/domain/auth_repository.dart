import '../../../core/error/result.dart';
import 'app_user.dart';

abstract interface class AuthRepository {
  /// Emits the current signed-in profile, or null when signed out.
  Stream<AppUser?> watchCurrentUser();

  Future<Result<AppUser>> signIn({required String email, required String password});

  Future<void> signOut();
}
