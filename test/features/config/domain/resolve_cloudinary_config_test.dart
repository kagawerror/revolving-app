import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/config/domain/cloudinary_config.dart';
import 'package:rev_app/features/config/domain/resolve_cloudinary_config.dart';

void main() {
  const fallback = CloudinaryConfig(
    cloudName: 'fallback-cloud',
    uploadPreset: 'fallback-upload',
    signaturePreset: 'fallback-sig-preset',
    uploadFolder: 'fallback/uploads',
    signatureFolder: 'fallback/sigs',
    apiKey: 'fallback-key',
  );

  test('remote null uses fallback for every field', () {
    final eff = resolveCloudinaryConfig(remote: null, fallback: fallback);

    expect(eff.cloudName, 'fallback-cloud');
    expect(eff.uploadPreset, 'fallback-upload');
    expect(eff.signaturePreset, 'fallback-sig-preset');
    expect(eff.uploadFolder, 'fallback/uploads');
    expect(eff.signatureFolder, 'fallback/sigs');
  });

  test('fully-populated remote overrides every field', () {
    const remote = CloudinaryConfig(
      cloudName: 'remote-cloud',
      uploadPreset: 'remote-upload',
      signaturePreset: 'remote-sig-preset',
      uploadFolder: 'remote/uploads',
      signatureFolder: 'remote/sigs',
      apiKey: 'remote-key',
    );

    final eff = resolveCloudinaryConfig(remote: remote, fallback: fallback);

    expect(eff.cloudName, 'remote-cloud');
    expect(eff.uploadPreset, 'remote-upload');
    expect(eff.signaturePreset, 'remote-sig-preset');
    expect(eff.uploadFolder, 'remote/uploads');
    expect(eff.signatureFolder, 'remote/sigs');
  });

  test('partial remote merges field-by-field (empty fields fall back)', () {
    const remote = CloudinaryConfig(
      cloudName: 'remote-cloud',
      uploadPreset: '', // empty -> fallback
      signaturePreset: 'remote-sig-preset',
      uploadFolder: '', // empty -> fallback
      signatureFolder: 'remote/sigs',
    );

    final eff = resolveCloudinaryConfig(remote: remote, fallback: fallback);

    expect(eff.cloudName, 'remote-cloud');
    expect(eff.uploadPreset, 'fallback-upload');
    expect(eff.signaturePreset, 'remote-sig-preset');
    expect(eff.uploadFolder, 'fallback/uploads');
    expect(eff.signatureFolder, 'remote/sigs');
  });

  test('empty signaturePreset falls back to uploadPreset via effective getter',
      () {
    final eff = resolveCloudinaryConfig(
      remote: const CloudinaryConfig(
        cloudName: 'c',
        uploadPreset: 'the-upload-preset',
        signaturePreset: '',
      ),
      fallback: const CloudinaryConfig(cloudName: '', uploadPreset: ''),
    );

    expect(eff.signaturePreset, '');
    expect(eff.signatureEffectivePreset, 'the-upload-preset');
  });

  test('isConfigured is true only when cloudName and uploadPreset both set', () {
    final configured = resolveCloudinaryConfig(
      remote: const CloudinaryConfig(cloudName: 'c', uploadPreset: 'p'),
      fallback: CloudinaryConfig.empty,
    );
    expect(configured.isConfigured, isTrue);

    final missing = resolveCloudinaryConfig(
      remote: null,
      fallback: CloudinaryConfig.empty,
    );
    expect(missing.isConfigured, isFalse);
  });
}
