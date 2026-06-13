import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/update/data/update_skip_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('UpdateSkipStore', () {
    test('defaults to 0 when nothing was skipped', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = UpdateSkipStore(prefs);
      expect(store.skippedVersionCode(), 0);
    });

    test('skip persists the version code', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = UpdateSkipStore(prefs);

      await store.skip(5);
      expect(store.skippedVersionCode(), 5);
    });

    test('skip is monotonic: never lowers the stored code', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = UpdateSkipStore(prefs);

      await store.skip(7);
      await store.skip(3); // older manifest must not un-skip a newer one
      expect(store.skippedVersionCode(), 7);
    });
  });
}
