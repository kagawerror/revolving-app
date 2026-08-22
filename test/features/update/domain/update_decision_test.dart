import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/update/domain/app_version_info.dart';
import 'package:rev_app/features/update/domain/update_decision.dart';

AppVersionInfo _info(int code) => AppVersionInfo(
      versionCode: code,
      versionName: '1.$code.0',
      apkUrl: 'https://h/a-$code.apk',
    );

void main() {
  group('decideUpdate', () {
    test('null manifest -> upToDate (fail safe, never nag)', () {
      final d = decideUpdate(currentVersionCode: 1, latest: null);
      expect(d.status, UpdateStatus.upToDate);
      expect(d.hasUpdate, isFalse);
    });

    test('newer manifest -> updateAvailable carries the manifest', () {
      final d = decideUpdate(currentVersionCode: 1, latest: _info(2));
      expect(d.status, UpdateStatus.updateAvailable);
      expect(d.hasUpdate, isTrue);
      expect(d.latest!.versionCode, 2);
    });

    test('equal version -> upToDate', () {
      final d = decideUpdate(currentVersionCode: 2, latest: _info(2));
      expect(d.status, UpdateStatus.upToDate);
    });

    test('older manifest -> upToDate (never downgrade)', () {
      final d = decideUpdate(currentVersionCode: 3, latest: _info(2));
      expect(d.status, UpdateStatus.upToDate);
    });

    test('newer manifest the user skipped -> upToDate (no nag loop)', () {
      final d = decideUpdate(
        currentVersionCode: 1,
        latest: _info(2),
        skippedVersionCode: 2,
      );
      expect(d.status, UpdateStatus.upToDate);
      expect(d.hasUpdate, isFalse);
    });

    test('manifest newer than the skipped one -> updateAvailable again', () {
      final d = decideUpdate(
        currentVersionCode: 1,
        latest: _info(3),
        skippedVersionCode: 2,
      );
      expect(d.status, UpdateStatus.updateAvailable);
      expect(d.latest!.versionCode, 3);
    });
  });
}
