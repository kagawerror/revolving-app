import '../../../core/error/result.dart';
import 'cloudinary_config.dart';

/// Read/write access to the single global `appConfig/cloudinary` document.
/// `null` everywhere means "not provisioned yet" — callers fall back to
/// build-time `AppSecrets`.
abstract interface class CloudinaryConfigRepository {
  /// Live stream of the config; emits `null` while the doc does not exist.
  Stream<CloudinaryConfig?> watch();

  /// One-shot read. `Ok(null)` when the doc is absent.
  Future<Result<CloudinaryConfig?>> get();

  /// Merges the given config into the doc (admin only at the rules layer).
  Future<Result<void>> upsert(CloudinaryConfig config, String actorUid);
}
