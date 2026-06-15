import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/admin_users/domain/admin_password_repository.dart';
import 'package:rev_app/features/admin_users/domain/user_admin_repository.dart';
import 'package:rev_app/features/admin_users/presentation/reset_user_password.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';

class _MockUserAdminRepository extends Mock implements UserAdminRepository {}

class _MockAdminPasswordRepository extends Mock
    implements AdminPasswordRepository {}

const _target = AppUser(
  uid: 'u1',
  companyId: 'c1',
  companyIds: ['c1'],
  role: UserRole.incharge,
  displayName: 'Jane',
  email: 'jane@acme.com',
);

void main() {
  late _MockUserAdminRepository userRepo;
  late _MockAdminPasswordRepository passwordRepo;

  setUp(() {
    userRepo = _MockUserAdminRepository();
    passwordRepo = _MockAdminPasswordRepository();
  });

  Future<String?> run(String newPassword) => resetUserPassword(
        target: _target,
        newPassword: newPassword,
        adminPasswordRepository: passwordRepo,
        userAdminRepository: userRepo,
      );

  void stubSetPasswordOk() {
    when(() => passwordRepo.setUserPassword(
          uid: any(named: 'uid'),
          newPassword: any(named: 'newPassword'),
        )).thenAnswer((_) async => const Ok(null));
  }

  void stubFlagOk() {
    when(() => userRepo.setMustChangePassword(
          uid: any(named: 'uid'),
          value: any(named: 'value'),
        )).thenAnswer((_) async => const Ok(null));
  }

  test('relay success + flag success: returns null, both called in order',
      () async {
    stubSetPasswordOk();
    stubFlagOk();

    final message = await run('newpass123');

    expect(message, isNull);
    verifyInOrder([
      () => passwordRepo.setUserPassword(uid: 'u1', newPassword: 'newpass123'),
      () => userRepo.setMustChangePassword(uid: 'u1', value: true),
    ]);
  });

  test('relay failure: surfaces message, flag NOT called', () async {
    const failure = UnexpectedFailure('Could not set the password. Try again.');
    when(() => passwordRepo.setUserPassword(
          uid: any(named: 'uid'),
          newPassword: any(named: 'newPassword'),
        )).thenAnswer((_) async => const Err(failure));

    final message = await run('newpass123');

    expect(message, failure.message);
    verifyNever(() => userRepo.setMustChangePassword(
          uid: any(named: 'uid'),
          value: any(named: 'value'),
        ));
  });

  test('relay success + flag failure: recoverable message', () async {
    stubSetPasswordOk();
    when(() => userRepo.setMustChangePassword(
          uid: any(named: 'uid'),
          value: any(named: 'value'),
        )).thenAnswer(
        (_) async => const Err(UnexpectedFailure('flag write failed')));

    final message = await run('newpass123');

    expect(
      message,
      "Password was reset, but couldn't flag the account. Try again.",
    );
  });

  test('invalid password: validation message, relay NOT called', () async {
    final message = await run('123'); // below the minimum length

    expect(message, isNotNull);
    verifyNever(() => passwordRepo.setUserPassword(
          uid: any(named: 'uid'),
          newPassword: any(named: 'newPassword'),
        ));
    verifyNever(() => userRepo.setMustChangePassword(
          uid: any(named: 'uid'),
          value: any(named: 'value'),
        ));
  });
}
