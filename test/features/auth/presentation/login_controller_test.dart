import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/domain/auth_repository.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/auth/presentation/login_controller.dart';

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
    expect(c.read(loginControllerProvider), const LoginState.idle());
  });

  test('failed sign-in sets error state', () async {
    when(() => repo.signIn(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => const Err(AuthFailure('Incorrect email or password.')));
    final c = makeContainer();
    addTearDown(c.dispose);
    await c.read(loginControllerProvider.notifier).submit('a@b.com', 'x');
    expect(c.read(loginControllerProvider),
        const LoginState.error('Incorrect email or password.'));
  });

  test('successful sign-in sets success state', () async {
    when(() => repo.signIn(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => const Ok(AppUser(
            uid: 'u', companyId: 'c', role: UserRole.incharge,
            displayName: 'A', email: 'a@b.com')));
    final c = makeContainer();
    addTearDown(c.dispose);
    await c.read(loginControllerProvider.notifier).submit('a@b.com', 'pw');
    expect(c.read(loginControllerProvider), const LoginState.success());
  });
}
