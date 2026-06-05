import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/admin_users/domain/user_assignment.dart';

void main() {
  const companies = {'c1', 'c2'};

  ValidationFailure? validate({
    String displayName = 'Jane',
    String email = 'jane@acme.com',
    UserRole role = UserRole.incharge,
    String companyId = 'c1',
    List<String> companyIds = const ['c1'],
    String? password,
    String? confirmPassword,
    bool validateEmail = true,
  }) =>
      validateUserAssignment(
        displayName: displayName,
        email: email,
        role: role,
        companyId: companyId,
        companyIds: companyIds,
        existingCompanyIds: companies,
        password: password,
        confirmPassword: confirmPassword,
        validateEmail: validateEmail,
      );

  test('valid non-admin CREATE (with matching passwords) returns null', () {
    expect(
      validate(password: 'secret1', confirmPassword: 'secret1'),
      isNull,
    );
  });

  test('valid non-admin EDIT (no password fields) returns null', () {
    expect(validate(validateEmail: false), isNull);
  });

  test('valid admin (no company, no memberships) CREATE returns null', () {
    expect(
      validate(
        role: UserRole.admin,
        companyId: '',
        companyIds: const [],
        password: 'secret1',
        confirmPassword: 'secret1',
      ),
      isNull,
    );
  });

  test('valid multi-company non-admin returns null', () {
    expect(
      validate(
        companyId: 'c1',
        companyIds: const ['c1', 'c2'],
        password: 'secret1',
        confirmPassword: 'secret1',
      ),
      isNull,
    );
  });

  test('empty display name is rejected', () {
    final f = validate(displayName: '   ');
    expect(f!.message, 'A display name is required.');
  });

  test('empty email is rejected on create path', () {
    final f = validate(email: '');
    expect(f!.message, 'A valid email is required.');
  });

  test('invalid email is rejected on create path', () {
    final f = validate(email: 'not-an-email');
    expect(f!.message, 'A valid email is required.');
  });

  test('email is not validated when validateEmail is false (edit path)', () {
    // Edit passes through whatever immutable email exists on the doc.
    expect(validate(email: '', validateEmail: false), isNull);
  });

  test('short password is rejected on create path', () {
    final f = validate(password: '12345', confirmPassword: '12345');
    expect(f!.message, 'Use a password of at least 6 characters.');
  });

  test('mismatched passwords are rejected on create path', () {
    final f = validate(password: 'secret1', confirmPassword: 'secret2');
    expect(f!.message, 'Passwords do not match.');
  });

  test('password is not checked on edit path (password null)', () {
    // EDIT never supplies a password; the password branch is skipped.
    expect(validate(password: null, confirmPassword: null), isNull);
  });

  test('admin with a companyId is rejected', () {
    final f = validate(
      role: UserRole.admin,
      companyId: 'c1',
      companyIds: const [],
      password: 'secret1',
      confirmPassword: 'secret1',
    );
    expect(f!.message, 'Admins are not assigned to a company.');
  });

  test('admin with non-empty companyIds is rejected', () {
    final f = validate(
      role: UserRole.admin,
      companyId: '',
      companyIds: const ['c1'],
      password: 'secret1',
      confirmPassword: 'secret1',
    );
    expect(f!.message, 'Admins are not assigned to a company.');
  });

  test('non-admin with empty memberships is rejected', () {
    final f = validate(companyId: '', companyIds: const []);
    expect(f!.message, 'Select an existing company.');
  });

  test('non-admin with an unknown membership id is rejected', () {
    final f = validate(companyId: 'c1', companyIds: const ['c1', 'nope']);
    expect(f!.message, 'Select an existing company.');
  });

  test('non-admin whose primary is not in the membership list is rejected', () {
    final f = validate(companyId: 'c2', companyIds: const ['c1']);
    expect(f!.message, 'Select an existing company.');
  });

  test('non-admin with duplicate membership ids is rejected', () {
    final f = validate(companyId: 'c1', companyIds: const ['c1', 'c1']);
    expect(f!.message, 'Select an existing company.');
  });

  test('password check runs BEFORE role/company branching', () {
    // A non-admin with a bad password AND no company still reports the
    // password problem first (password is validated before the role branch).
    final f = validate(
      companyId: '',
      companyIds: const [],
      password: '123',
      confirmPassword: '123',
    );
    expect(f!.message, 'Use a password of at least 6 characters.');
  });
}
