import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_secrets.dart';
import '../../../services/cloudinary/cloudinary_uploader.dart';
import '../../auth/presentation/auth_providers.dart';
import 'profile_controller.dart';

/// Uploads avatars to a dedicated Cloudinary folder, reusing the proof uploader.
final avatarUploaderProvider = Provider<CloudinaryUploader>((ref) {
  return CloudinaryUploader(
    cloudName: AppSecrets.cloudinaryCloudName,
    uploadPreset: AppSecrets.cloudinaryUploadPreset,
    folder: 'avatars',
  );
});

final profileControllerProvider = Provider<ProfileController>(
  (ref) => ProfileController(ref.watch(authRepositoryProvider)),
);
