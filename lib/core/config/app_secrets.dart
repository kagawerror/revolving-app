/// Build-time configuration injected via `--dart-define` (or `--dart-define-from-file=.env`).
/// No secret is hard-coded here; the Cloudinary upload uses an UNSIGNED preset, so the
/// Cloudinary API secret is never present in the app.
class AppSecrets {
  const AppSecrets._();

  static const String cloudinaryCloudName =
      String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
  static const String cloudinaryUploadPreset =
      String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');
  static const String cloudinaryUploadFolder =
      String.fromEnvironment('CLOUDINARY_UPLOAD_FOLDER', defaultValue: 'rev_app/proofs');

  static bool get hasCloudinary =>
      cloudinaryCloudName.isNotEmpty && cloudinaryUploadPreset.isNotEmpty;
}
