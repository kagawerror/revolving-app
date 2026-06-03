import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_secrets.dart';
import '../../../services/cloudinary/cloudinary_uploader.dart';
import '../../../services/firebase/firebase_providers.dart';
import '../../../services/image/image_pick_compress.dart';
import '../data/firestore_request_repository.dart';
import '../domain/request_repository.dart';

final requestRepositoryProvider = Provider<RequestRepository>(
    (ref) => FirestoreRequestRepository(ref.watch(firestoreProvider)));

final cloudinaryUploaderProvider = Provider<CloudinaryUploader>((ref) =>
    CloudinaryUploader(
      cloudName: AppSecrets.cloudinaryCloudName,
      uploadPreset: AppSecrets.cloudinaryUploadPreset,
      folder: AppSecrets.cloudinaryUploadFolder,
    ));

final imagePickCompressProvider =
    Provider<ImagePickCompress>((ref) => ImagePickCompress());
