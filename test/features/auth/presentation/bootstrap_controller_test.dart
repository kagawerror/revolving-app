import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/domain/auth_repository.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/auth/presentation/bootstrap_controller.dart';

class _MockRepo extends Mock implements AuthRepository {}

void main() {
  late _MockRepo repo;
  setUp(() => repo = _MockRepo());

  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );

  test('initial state is idle', () {
    final c = makeContainer();
    addTearDown(c.dispose);
    expect(c.read(bootstrapControllerProvider), const BootstrapState.idle());
  });

  test('failed bootstrap sets error state', () async {
    when(() => repo.bootstrapFirstAdmin(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        )).thenAnswer(
        (_) async => const Err(PermissionFailure('Setup was already completed.')));
    final c = makeContainer();
    addTearDown(c.dispose);

    await c
        .read(bootstrapControllerProvider.notifier)
        .submit('a@b.com', 'secret1', 'Ada');

    expect(c.read(bootstrapControllerProvider),
        const BootstrapState.error('Setup was already completed.'));
  });

  test('successful bootstrap sets success state', () async {
    when(() => repo.bootstrapFirstAdmin(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        )).thenAnswer((_) async => const Ok(AppUser(
          uid: 'u',
          companyId: '',
          role: UserRole.admin,
          displayName: 'Ada',
          email: 'a@b.com',
        )));
    final c = makeContainer();
    addTearDown(c.dispose);

    await c
        .read(bootstrapControllerProvider.notifier)
        .submit('a@b.com', 'secret1', 'Ada');

    expect(c.read(bootstrapControllerProvider), const BootstrapState.success());
  });
}
