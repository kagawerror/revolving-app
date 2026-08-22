import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../domain/cloudinary_config.dart';
import 'config_providers.dart';

/// Save-side controller for the admin Cloudinary screen. State is `isSaving`.
class CloudinaryConfigController extends AutoDisposeNotifier<bool> {
  @override
  bool build() => false; // saving?

  Future<Result<void>> save(CloudinaryConfig draft, String actorUid) async {
    state = true;
    try {
      return await ref
          .read(cloudinaryConfigRepositoryProvider)
          .upsert(draft, actorUid);
    } finally {
      state = false;
    }
  }
}

final cloudinaryConfigControllerProvider =
    NotifierProvider.autoDispose<CloudinaryConfigController, bool>(
        CloudinaryConfigController.new);
