import 'package:equatable/equatable.dart';

import 'cloudinary_config.dart';

/// The fully-resolved Cloudinary settings the app actually uploads with: a
/// field-by-field merge of the remote (admin-managed) config over the build-time
/// fallback. Every field is non-nullable here — callers never reason about
/// blanks again.
class EffectiveCloudinaryConfig extends Equatable {
  final String cloudName;
  final String uploadPreset;
  final String uploadFolder;
  final String signaturePreset;
  final String signatureFolder;

  const EffectiveCloudinaryConfig({
    required this.cloudName,
    required this.uploadPreset,
    required this.uploadFolder,
    required this.signaturePreset,
    required this.signatureFolder,
  });

  /// The preset actually used for signature uploads: the dedicated one when set,
  /// otherwise the shared upload preset.
  String get signatureEffectivePreset =>
      signaturePreset.isNotEmpty ? signaturePreset : uploadPreset;

  /// Uploads can proceed only when both the cloud name and upload preset resolve
  /// to a non-empty value.
  bool get isConfigured => cloudName.isNotEmpty && uploadPreset.isNotEmpty;

  @override
  List<Object?> get props => [
        cloudName,
        uploadPreset,
        uploadFolder,
        signaturePreset,
        signatureFolder,
      ];
}

/// Field-by-field merge: each [remote] field is used only when non-empty,
/// otherwise the matching [fallback] field. Pure — no AppSecrets/Firebase here.
EffectiveCloudinaryConfig resolveCloudinaryConfig({
  CloudinaryConfig? remote,
  required CloudinaryConfig fallback,
}) {
  String pick(String? remoteValue, String fallbackValue) =>
      (remoteValue != null && remoteValue.isNotEmpty)
          ? remoteValue
          : fallbackValue;

  return EffectiveCloudinaryConfig(
    cloudName: pick(remote?.cloudName, fallback.cloudName),
    uploadPreset: pick(remote?.uploadPreset, fallback.uploadPreset),
    uploadFolder: pick(remote?.uploadFolder, fallback.uploadFolder),
    signaturePreset: pick(remote?.signaturePreset, fallback.signaturePreset),
    signatureFolder: pick(remote?.signatureFolder, fallback.signatureFolder),
  );
}
