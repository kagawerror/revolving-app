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

  // Recipient-signature uploads live in their own folder and may use a dedicated
  // preset. When the preset is blank we reuse the proof upload preset (see
  // [cloudinarySignatureEffectivePreset]). Signatures are PNG, not JPEG.
  static const String cloudinarySignatureFolder = String.fromEnvironment(
      'CLOUDINARY_SIGNATURE_FOLDER',
      defaultValue: 'rev_app/signatures');
  static const String cloudinarySignaturePreset =
      String.fromEnvironment('CLOUDINARY_SIGNATURE_PRESET');

  /// The preset actually used for signature uploads: the dedicated one when set,
  /// otherwise the shared proof upload preset.
  static String get cloudinarySignatureEffectivePreset =>
      cloudinarySignaturePreset.isNotEmpty
          ? cloudinarySignaturePreset
          : cloudinaryUploadPreset;

  // Phase 2 seam: when set, signature uploads route through this relay (for
  // signed/relayed uploads). Blank in Phase 1 — uploads go directly, unsigned.
  static const String signatureRelayUrl =
      String.fromEnvironment('SIGNATURE_RELAY_URL');

  static bool get hasCloudinary =>
      cloudinaryCloudName.isNotEmpty && cloudinaryUploadPreset.isNotEmpty;

  static bool get hasSignatureRelay => signatureRelayUrl.isNotEmpty;

  static const String oneSignalAppId =
      String.fromEnvironment('ONESIGNAL_APP_ID');
  static const String pushRelayUrl =
      String.fromEnvironment('PUSH_RELAY_URL');
  static const String pushRelayToken =
      String.fromEnvironment('PUSH_RELAY_TOKEN');

  static const String adminRelayUrl =
      String.fromEnvironment('ADMIN_RELAY_URL');

  // Public, read-only HTTPS URL of the self-hosted update manifest (version.json).
  // Safe to embed: it grants no write access. Blank disables update checks.
  static const String updateManifestUrl =
      String.fromEnvironment('UPDATE_MANIFEST_URL');

  static bool get hasOneSignal => oneSignalAppId.isNotEmpty;
  static bool get hasPushRelay => pushRelayUrl.isNotEmpty;
  static bool get hasAdminRelay => adminRelayUrl.isNotEmpty;
  static bool get hasUpdates => updateManifestUrl.isNotEmpty;
}
