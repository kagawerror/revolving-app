import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/update/data/update_repository.dart';
import 'package:rev_app/features/update/domain/app_version_info.dart';
import 'package:rev_app/features/update/domain/update_decision.dart';
import 'package:rev_app/features/update/presentation/update_providers.dart';

class _FakeRepo implements UpdateRepository {
  _FakeRepo(this._result);
  final Result<AppVersionInfo> _result;
  @override
  Future<Result<AppVersionInfo>> fetchLatest() async => _result;
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
    ]);
    addTearDown(container.dispose);

    final decision = await container.read(updateCheckProvider.future);
    expect(decision.status, UpdateStatus.updateAvailable);
    expect(decision.latest!.versionCode, 99);
  });

  test('updateCheckProvider short-circuits to upToDate on unsupported platform',
      () async {
    final container = ProviderContainer(overrides: [
      updateRepositoryProvider.overrideWithValue(
        _FakeRepo(const Err(UnexpectedFailure('should not be called'))),
      ),
      currentVersionCodeProvider.overrideWith((ref) async => 1),
      isUpdateSupportedPlatformProvider.overrideWithValue(false),
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
    ]);
    addTearDown(container.dispose);

    final decision = await container.read(updateCheckProvider.future);
    expect(decision.status, UpdateStatus.upToDate);
  });
}
