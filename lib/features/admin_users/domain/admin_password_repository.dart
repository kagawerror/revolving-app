import '../../../core/error/result.dart';

/// Admin-only "set/reset another user's password" capability.
///
/// On the Spark tier there are no Cloud Functions, so this is fulfilled by an
/// out-of-band Cloudflare Worker (Firebase Admin SDK behind it) the app calls
/// over HTTP. Like every repository, methods return a [Result] and never throw.
abstract class AdminPasswordRepository {
  /// Sets [uid]'s sign-in password to [newPassword]. [newPassword] is transient
  /// and must never be logged or persisted by implementations.
  Future<Result<void>> setUserPassword({
    required String uid,
    required String newPassword,
  });
}
