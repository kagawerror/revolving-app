import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_secrets.dart';
import '../../../core/error/result.dart';
import '../../../services/cloudinary/cloudinary_uploader.dart';
import '../../../services/firebase/firebase_providers.dart';
import '../../../services/image/image_pick_compress.dart';
import '../../config/presentation/config_providers.dart';
import '../../messaging/presentation/messaging_providers.dart';
import '../data/firestore_request_repository.dart';
import '../domain/request_repository.dart';

final requestRepositoryProvider = Provider<RequestRepository>((ref) =>
    FirestoreRequestRepository(
        ref.watch(firestoreProvider), ref.watch(pushSenderProvider)));

final cloudinaryUploaderProvider = Provider<CloudinaryUploader>((ref) {
  final cfg = ref.watch(effectiveCloudinaryConfigProvider);
  return CloudinaryUploader(
    cloudName: cfg.cloudName,
    uploadPreset: cfg.uploadPreset,
    folder: cfg.uploadFolder,
  );
});

/// Uploads a recipient-signature PNG and yields its URL. A single swappable
/// function so Phase 2 (relay-signed uploads) is a localized change here, not a
/// churn across the release controller.
typedef SignatureUpload = Future<Result<String>> Function(Uint8List pngBytes);

final signatureUploadProvider = Provider<SignatureUpload>((ref) {
  final uploader = ref.watch(cloudinaryUploaderProvider);
  final cfg = ref.watch(effectiveCloudinaryConfigProvider);
  return (Uint8List pngBytes) {
    if (AppSecrets.hasSignatureRelay) {
      // Phase 2: route through SIGNATURE_RELAY_URL (signed/relayed upload) and
      // return the same Result<String>. Not implemented in Phase 1 — fall
      // through to the direct unsigned upload below. Keep this branch the ONLY
      // place that needs to change when the relay lands.
    }
    // Phase 1: direct unsigned upload to the signatures folder with the
    // effective signature preset (dedicated, or the shared proof preset).
    return uploader.uploadPng(
      pngBytes,
      folder: cfg.signatureFolder,
      preset: cfg.signatureEffectivePreset,
    );
  };
});

final imagePickCompressProvider =
    Provider<ImagePickCompress>((ref) => ImagePickCompress());
