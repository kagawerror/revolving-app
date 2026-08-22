import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/cloudinary/cloudinary_uploader.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../config/presentation/config_providers.dart';
import 'profile_controller.dart';

/// Uploads avatars to a dedicated Cloudinary folder, reusing the proof uploader.
final avatarUploaderProvider = Provider<CloudinaryUploader>((ref) {
  final cfg = ref.watch(effectiveCloudinaryConfigProvider);
  return CloudinaryUploader(
    cloudName: cfg.cloudName,
    uploadPreset: cfg.uploadPreset,
    folder: 'avatars',
  );
});

final profileControllerProvider = Provider<ProfileController>(
  (ref) => ProfileController(ref.watch(authRepositoryProvider)),
);
