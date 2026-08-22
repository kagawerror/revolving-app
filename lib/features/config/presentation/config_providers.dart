import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_secrets.dart';
import '../../../services/firebase/firebase_providers.dart';
import '../data/firestore_cloudinary_config_repository.dart';
import '../domain/cloudinary_config.dart';
import '../domain/cloudinary_config_repository.dart';
import '../domain/resolve_cloudinary_config.dart';

final cloudinaryConfigRepositoryProvider =
    Provider<CloudinaryConfigRepository>((ref) =>
        FirestoreCloudinaryConfigRepository(ref.watch(firestoreProvider)));

final cloudinaryConfigStreamProvider =
    StreamProvider.autoDispose<CloudinaryConfig?>(
        (ref) => ref.watch(cloudinaryConfigRepositoryProvider).watch());

/// The ONLY place the presentation layer reads `AppSecrets` for Cloudinary —
/// the build-time fallback used field-by-field when the remote doc is missing
/// or blank. (apiKey isn't an AppSecret, so it has no build-time fallback.)
final appSecretsFallbackProvider = Provider<CloudinaryConfig>((ref) =>
    CloudinaryConfig(
      cloudName: AppSecrets.cloudinaryCloudName,
      uploadPreset: AppSecrets.cloudinaryUploadPreset,
      signaturePreset: AppSecrets.cloudinarySignaturePreset,
      uploadFolder: AppSecrets.cloudinaryUploadFolder,
      signatureFolder: AppSecrets.cloudinarySignatureFolder,
    ));

/// Synchronous resolved config. While the stream is loading (valueOrNull ==
/// null) it returns the fallback, so uploaders never block on the network.
final effectiveCloudinaryConfigProvider =
    Provider.autoDispose<EffectiveCloudinaryConfig>((ref) =>
        resolveCloudinaryConfig(
          remote: ref.watch(cloudinaryConfigStreamProvider).valueOrNull,
          fallback: ref.watch(appSecretsFallbackProvider),
        ));
