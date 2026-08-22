import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/config/domain/cloudinary_config.dart';
import 'package:rev_app/features/config/domain/cloudinary_config_repository.dart';
import 'package:rev_app/features/config/presentation/cloudinary_config_controller.dart';
import 'package:rev_app/features/config/presentation/config_providers.dart';

class _MockRepo extends Mock implements CloudinaryConfigRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(CloudinaryConfig.empty);
  });

  const draft = CloudinaryConfig(cloudName: 'cloud', uploadPreset: 'up');

  test('save delegates to repo.upsert and returns Ok', () async {
    final repo = _MockRepo();
    when(() => repo.upsert(any(), any()))
        .thenAnswer((_) async => const Ok(null));

    final c = ProviderContainer(overrides: [
      cloudinaryConfigRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);

    final ctrl = c.read(cloudinaryConfigControllerProvider.notifier);
    final res = await ctrl.save(draft, 'actor-1');

    expect(res.isOk, isTrue);
    verify(() => repo.upsert(draft, 'actor-1')).called(1);
    // Settles back to not-saving.
    expect(c.read(cloudinaryConfigControllerProvider), isFalse);
  });

  test('save surfaces an Err from the repo', () async {
    final repo = _MockRepo();
    when(() => repo.upsert(any(), any()))
        .thenAnswer((_) async => const Err(UnexpectedFailure('nope')));

    final c = ProviderContainer(overrides: [
      cloudinaryConfigRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);

    final res =
        await c.read(cloudinaryConfigControllerProvider.notifier).save(draft, 'a');

    expect(res.failureOrNull, isA<UnexpectedFailure>());
    expect(c.read(cloudinaryConfigControllerProvider), isFalse);
  });

  test('isSaving toggles true while the upsert is in flight', () async {
    final repo = _MockRepo();
    final gate = Completer<Result<void>>();
    when(() => repo.upsert(any(), any())).thenAnswer((_) => gate.future);

    final c = ProviderContainer(overrides: [
      cloudinaryConfigRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);

    final ctrl = c.read(cloudinaryConfigControllerProvider.notifier);
    expect(c.read(cloudinaryConfigControllerProvider), isFalse);

    final future = ctrl.save(draft, 'a');
    expect(c.read(cloudinaryConfigControllerProvider), isTrue);

    gate.complete(const Ok(null));
    await future;
    expect(c.read(cloudinaryConfigControllerProvider), isFalse);
  });
}
