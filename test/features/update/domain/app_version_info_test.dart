import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/update/domain/app_version_info.dart';

void main() {
  group('AppVersionInfo.fromMap', () {
    test('parses a complete, valid manifest', () {
      final info = AppVersionInfo.fromMap({
        'versionCode': 2,
        'versionName': '1.1.0',
        'apkUrl': 'https://h/app/rev_app-1.1.0+2.apk',
        'notes': 'Fixes',
      });
      expect(info, isNotNull);
      expect(info!.versionCode, 2);
      expect(info.versionName, '1.1.0');
      expect(info.apkUrl, 'https://h/app/rev_app-1.1.0+2.apk');
      expect(info.notes, 'Fixes');
    });

    test('treats empty notes as null', () {
      final info = AppVersionInfo.fromMap({
        'versionCode': 2,
        'versionName': '1.1.0',
        'apkUrl': 'https://h/a.apk',
        'notes': '',
      });
      expect(info!.notes, isNull);
    });

    test('returns null when versionCode is missing or not an int', () {
      expect(
        AppVersionInfo.fromMap(
            {'versionName': '1.1.0', 'apkUrl': 'https://h/a.apk'}),
        isNull,
      );
      expect(
        AppVersionInfo.fromMap({
          'versionCode': '2',
          'versionName': '1.1.0',
          'apkUrl': 'https://h/a.apk',
        }),
        isNull,
      );
    });

    test('returns null when apkUrl is empty', () {
      expect(
        AppVersionInfo.fromMap(
            {'versionCode': 2, 'versionName': '1.1.0', 'apkUrl': ''}),
        isNull,
      );
    });
  });
}
