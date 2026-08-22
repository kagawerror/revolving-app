import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/config/domain/cloudinary_config.dart';

void main() {
  group('fromMap', () {
    test('coerces null/missing fields to empty strings', () {
      final c = CloudinaryConfig.fromMap(<String, dynamic>{});

      expect(c.cloudName, '');
      expect(c.uploadPreset, '');
      expect(c.signaturePreset, '');
      expect(c.uploadFolder, '');
      expect(c.signatureFolder, '');
      expect(c.apiKey, '');
      expect(c.updatedByUid, '');
      expect(c.updatedAt, isNull);
    });

    test('reads all public fields and parses Timestamp updatedAt', () {
      final ts = Timestamp.fromDate(DateTime.utc(2026, 1, 2, 3, 4, 5));
      final c = CloudinaryConfig.fromMap(<String, dynamic>{
        'cloudName': 'cloud',
        'uploadPreset': 'up',
        'signaturePreset': 'sp',
        'uploadFolder': 'uf',
        'signatureFolder': 'sf',
        'apiKey': 'key',
        'updatedAt': ts,
        'updatedByUid': 'actor-1',
      });

      expect(c.cloudName, 'cloud');
      expect(c.uploadPreset, 'up');
      expect(c.signaturePreset, 'sp');
      expect(c.uploadFolder, 'uf');
      expect(c.signatureFolder, 'sf');
      expect(c.apiKey, 'key');
      expect(c.updatedByUid, 'actor-1');
      expect(c.updatedAt, ts.toDate());
    });
  });

  group('toUpdateMap', () {
    test('carries the 6 public fields, actor uid and a server timestamp', () {
      const c = CloudinaryConfig(
        cloudName: 'cloud',
        uploadPreset: 'up',
        signaturePreset: 'sp',
        uploadFolder: 'uf',
        signatureFolder: 'sf',
        apiKey: 'key',
      );

      final m = c.toUpdateMap('actor-9');

      expect(m['cloudName'], 'cloud');
      expect(m['uploadPreset'], 'up');
      expect(m['signaturePreset'], 'sp');
      expect(m['uploadFolder'], 'uf');
      expect(m['signatureFolder'], 'sf');
      expect(m['apiKey'], 'key');
      expect(m['updatedByUid'], 'actor-9');
      expect(m['updatedAt'], isA<FieldValue>());
      // Never persists a secret.
      expect(m.containsKey('apiSecret'), isFalse);
    });
  });

  test('signatureEffectivePreset falls back to uploadPreset when blank', () {
    const blank = CloudinaryConfig(cloudName: 'c', uploadPreset: 'up');
    expect(blank.signatureEffectivePreset, 'up');

    const set = CloudinaryConfig(
      cloudName: 'c',
      uploadPreset: 'up',
      signaturePreset: 'sp',
    );
    expect(set.signatureEffectivePreset, 'sp');
  });

  test('Equatable: equal field-for-field, distinct when one differs', () {
    final a = CloudinaryConfig.fromMap(const {'cloudName': 'c', 'uploadPreset': 'p'});
    final b = CloudinaryConfig.fromMap(const {'cloudName': 'c', 'uploadPreset': 'p'});
    final c = CloudinaryConfig.fromMap(const {'cloudName': 'x', 'uploadPreset': 'p'});

    expect(a, b);
    expect(a, isNot(c));
  });

  test('copyWith replaces only named fields', () {
    const base = CloudinaryConfig(cloudName: 'c', uploadPreset: 'p');
    final next = base.copyWith(uploadPreset: 'p2', apiKey: 'k');

    expect(next.cloudName, 'c');
    expect(next.uploadPreset, 'p2');
    expect(next.apiKey, 'k');
  });

  test('empty is a blank-but-valid const instance', () {
    expect(CloudinaryConfig.empty.cloudName, '');
    expect(CloudinaryConfig.empty.uploadPreset, '');
  });
}
