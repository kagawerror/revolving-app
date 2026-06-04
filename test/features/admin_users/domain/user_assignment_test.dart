import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/admin_users/domain/user_assignment.dart';

void main() {
  const companies = {'c1', 'c2'};

  ValidationFailure? validate({
    String uid = 'uid-1',
    String displayName = 'Jane',
    String email = 'jane@acme.com',
    UserRole role = UserRole.incharge,
    String companyId = 'c1',
    bool validateEmail = true,
  }) =>
      validateUserAssignment(
        uid: uid,
        displayName: displayName,
        email: email,
        role: role,
        companyId: companyId,
        existingCompanyIds: companies,
        validateEmail: validateEmail,
      );

  test('valid non-admin assignment returns null', () {
    expect(validate(), isNull);
  });

  test('valid admin (no company) returns null', () {
    expect(validate(role: UserRole.admin, companyId: ''), isNull);
  });

  test('empty uid is rejected', () {
    final f = validate(uid: '');
    expect(f, isA<ValidationFailure>());
    expect(f!.message, 'A Firebase user ID is required.');
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

  test('admin with a companyId is rejected', () {
    final f = validate(role: UserRole.admin, companyId: 'c1');
    expect(f!.message, 'Admins are not assigned to a company.');
  });

  test('non-admin with empty company is rejected', () {
    final f = validate(companyId: '');
    expect(f!.message, 'Select an existing company.');
  });

  test('non-admin with unknown company is rejected', () {
    final f = validate(companyId: 'nope');
    expect(f!.message, 'Select an existing company.');
  });
}
