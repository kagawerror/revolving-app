import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/update/data/update_repository.dart';
import 'package:rev_app/features/update/data/update_skip_store.dart';
import 'package:rev_app/features/update/domain/app_version_info.dart';
import 'package:rev_app/features/update/domain/update_decision.dart';
import 'package:rev_app/features/update/presentation/update_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepo implements UpdateRepository {
  _FakeRepo(this._result);
  final Result<AppVersionInfo> _result;
  @override
  Future<Result<AppVersionInfo>> fetchLatest() async => _result;
}

/// Builds an [UpdateSkipStore] seeded with [skipped] for provider overrides.
Future<UpdateSkipStore> _skipStore({int? skipped}) async {
  SharedPreferences.setMockInitialValues(
    skipped == null ? {} : {'update.skippedVersionCode': skipped},
  );
  return UpdateSkipStore(await SharedPreferences.getInstance());
}

void main() {
  test('updateCheckProvider returns updateAvailable when repo reports newer',
      () async {
    final container = ProviderContainer(overrides: [
      updateRepositoryProvider.overrideWithValue(
        _FakeRepo(const Ok(AppVersionInfo(
          versionCode: 99,
          versionName: '9.9.9',
          apkUrl: 'https://h/a.apk',
        ))),
      ),
      currentVersionCodeProvider.overrideWith((ref) async => 1),
      isUpdateSupportedPlatformProvider.overrideWithValue(true),
      updateSkipStoreProvider.overrideWithValue(await _skipStore()),
    ]);
    addTearDown(container.dispose);

    final decision = await container.read(updateCheckProvider.future);
    expect(decision.status, UpdateStatus.updateAvailable);
    expect(decision.latest!.versionCode, 99);
  });

  test('updateCheckProvider returns upToDate when the newer build was skipped',
      () async {
    final container = ProviderContainer(overrides: [
      updateRepositoryProvider.overrideWithValue(
        _FakeRepo(const Ok(AppVersionInfo(
          versionCode: 99,
          versionName: '9.9.9',
          apkUrl: 'https://h/a.apk',
        ))),
      ),
      currentVersionCodeProvider.overrideWith((ref) async => 1),
      isUpdateSupportedPlatformProvider.overrideWithValue(true),
      updateSkipStoreProvider.overrideWithValue(await _skipStore(skipped: 99)),
    ]);
    addTearDown(container.dispose);

    final decision = await container.read(updateCheckProvider.future);
    expect(decision.status, UpdateStatus.upToDate);
  });

  test('updateCheckProvider short-circuits to upToDate on unsupported platform',
      () async {
    final container = ProviderContainer(overrides: [
      updateRepositoryProvider.overrideWithValue(
        _FakeRepo(const Err(UnexpectedFailure('should not be called'))),
      ),
      currentVersionCodeProvider.overrideWith((ref) async => 1),
      isUpdateSupportedPlatformProvider.overrideWithValue(false),
      updateSkipStoreProvider.overrideWithValue(await _skipStore()),
    ]);
    addTearDown(container.dispose);

    final decision = await container.read(updateCheckProvider.future);
    expect(decision.status, UpdateStatus.upToDate);
  });

  test('updateCheckProvider returns upToDate when repo errs (fail safe)',
      () async {
    final container = ProviderContainer(overrides: [
      updateRepositoryProvider.overrideWithValue(
        _FakeRepo(const Err(UnexpectedFailure('offline'))),
      ),
      currentVersionCodeProvider.overrideWith((ref) async => 1),
      isUpdateSupportedPlatformProvider.overrideWithValue(true),
      updateSkipStoreProvider.overrideWithValue(await _skipStore()),
    ]);
    addTearDown(container.dispose);

    final decision = await container.read(updateCheckProvider.future);
    expect(decision.status, UpdateStatus.upToDate);
  });
}
