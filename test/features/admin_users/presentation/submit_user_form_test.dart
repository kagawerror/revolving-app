import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/admin_users/domain/admin_password_repository.dart';
import 'package:rev_app/features/admin_users/domain/user_admin_repository.dart';
import 'package:rev_app/features/admin_users/presentation/submit_user_form.dart';
import 'package:rev_app/features/admin_users/presentation/user_form_dialog.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/companies/domain/company.dart';
import 'package:rev_app/features/companies/domain/fund.dart';

class _MockUserAdminRepository extends Mock implements UserAdminRepository {}

class _MockAdminPasswordRepository extends Mock
    implements AdminPasswordRepository {}

const _companies = [Company(id: 'c1', name: 'Acme')];

final _funds = [
  Fund(
    id: 'f1',
    companyId: 'c1',
    name: 'Petty cash',
    originalBudget: Money.fromCentavos(100000),
    availableBalance: Money.fromCentavos(100000),
    lowBalanceThresholdPct: 3,
    status: FundStatus.active,
  ),
];

const _existing = AppUser(
  uid: 'u1',
  companyId: 'c1',
  companyIds: ['c1'],
  role: UserRole.incharge,
  displayName: 'Jane',
  email: 'jane@acme.com',
);

/// An EDIT submission. [newPassword]/[newConfirmPassword] default to empty
/// ("leave the password unchanged"); pass a value to request a reset.
UserFormSubmission _editSubmission({
  String displayName = 'Jane Updated',
  UserRole role = UserRole.superior,
  String newPassword = '',
  String? newConfirmPassword,
  List<String> fundIds = const [],
}) =>
    UserFormSubmission(
      displayName: displayName,
      email: _existing.email, // immutable on edit
      password: '', // CREATE-only, always empty on edit
      confirmPassword: '',
      newPassword: newPassword,
      newConfirmPassword: newConfirmPassword ?? newPassword,
      role: role,
      companyId: 'c1',
      companyIds: const ['c1'],
      fundIds: fundIds,
    );

void main() {
  late _MockUserAdminRepository userRepo;
  late _MockAdminPasswordRepository passwordRepo;

  setUpAll(() {
    // mocktail needs a fallback for the non-nullable enum used via any(named:).
    registerFallbackValue(UserRole.incharge);
  });

  setUp(() {
    userRepo = _MockUserAdminRepository();
    passwordRepo = _MockAdminPasswordRepository();
  });

  Future<String?> run(UserFormSubmission submission) => submitUserForm(
        submission: submission,
        existing: _existing,
        companies: _companies,
        funds: _funds,
        userAdminRepository: userRepo,
        adminPasswordRepository: passwordRepo,
      );

  void stubUpdateOk() {
    when(() => userRepo.updateAssignment(
          uid: any(named: 'uid'),
          role: any(named: 'role'),
          companyId: any(named: 'companyId'),
          companyIds: any(named: 'companyIds'),
          displayName: any(named: 'displayName'),
          assignedFundIds: any(named: 'assignedFundIds'),
        )).thenAnswer((_) async => const Ok(null));
  }

  group('edit orchestration', () {
    test(
        'profile ok + password ok: success, both called in order with right args',
        () async {
      stubUpdateOk();
      when(() => passwordRepo.setUserPassword(
            uid: any(named: 'uid'),
            newPassword: any(named: 'newPassword'),
          )).thenAnswer((_) async => const Ok(null));

      final message = await run(_editSubmission(newPassword: 'newpass123'));

      // null == success, nothing surfaced to the admin.
      expect(message, isNull);

      // Ordering is load-bearing: profile FIRST, password SECOND — and each is
      // called exactly once with the right args (edited profile fields; the
      // target uid + entered password). verifyInOrder asserts both presence,
      // count, and relative order in a single pass.
      verifyInOrder([
        () => userRepo.updateAssignment(
              uid: 'u1',
              role: UserRole.superior,
              companyId: 'c1',
              companyIds: ['c1'],
              displayName: 'Jane Updated',
            ),
        () => passwordRepo.setUserPassword(
              uid: 'u1',
              newPassword: 'newpass123',
            ),
      ]);
    });

    test(
        'profile ok + password FAILS: error surfaced, profile not rolled back',
        () async {
      stubUpdateOk();
      const failure = UnexpectedFailure('Could not set the password. Try again.');
      when(() => passwordRepo.setUserPassword(
            uid: any(named: 'uid'),
            newPassword: any(named: 'newPassword'),
          )).thenAnswer((_) async => const Err(failure));

      final message = await run(_editSubmission(newPassword: 'newpass123'));

      // The password failure's exact message is surfaced (not swallowed).
      expect(message, failure.message);

      // The profile update still happened — it is NOT rolled back.
      verify(() => userRepo.updateAssignment(
            uid: 'u1',
            role: UserRole.superior,
            companyId: 'c1',
            companyIds: ['c1'],
            displayName: 'Jane Updated',
          )).called(1);
      // And the password call was attempted (it's what failed).
      verify(() => passwordRepo.setUserPassword(
            uid: 'u1',
            newPassword: 'newpass123',
          )).called(1);
    });

    test('no new password entered: setUserPassword is never called', () async {
      stubUpdateOk();

      final message = await run(_editSubmission()); // newPassword empty

      expect(message, isNull);
      verify(() => userRepo.updateAssignment(
            uid: 'u1',
            role: UserRole.superior,
            companyId: 'c1',
            companyIds: ['c1'],
            displayName: 'Jane Updated',
          )).called(1);
      verifyNever(() => passwordRepo.setUserPassword(
            uid: any(named: 'uid'),
            newPassword: any(named: 'newPassword'),
          ));
    });
  });

  group('fund assignment', () {
    test('incharge fundIds reach the repo on update', () async {
      stubUpdateOk();

      final message = await run(_editSubmission(
        role: UserRole.incharge,
        fundIds: const ['f1'],
      ));

      expect(message, isNull);
      verify(() => userRepo.updateAssignment(
            uid: 'u1',
            role: UserRole.incharge,
            companyId: 'c1',
            companyIds: ['c1'],
            displayName: 'Jane Updated',
            assignedFundIds: ['f1'],
          )).called(1);
    });

    test('a fund outside the incharge companies is rejected before any write',
        () async {
      // _funds only knows f1 (in c1); f2 is unknown to the validator.
      final message = await run(_editSubmission(
        role: UserRole.incharge,
        fundIds: const ['f2'],
      ));

      expect(message, 'A selected fund is not in this user’s companies.');
      verifyNever(() => userRepo.updateAssignment(
            uid: any(named: 'uid'),
            role: any(named: 'role'),
            companyId: any(named: 'companyId'),
            companyIds: any(named: 'companyIds'),
            displayName: any(named: 'displayName'),
            assignedFundIds: any(named: 'assignedFundIds'),
          ));
    });
  });
}
