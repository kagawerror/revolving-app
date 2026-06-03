import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/routing/app_router.dart';

void main() {
  test('homeFor routes each role to its shell', () {
    expect(homeFor(UserRole.admin), '/admin');
    expect(homeFor(UserRole.incharge), '/incharge');
    expect(homeFor(UserRole.manager), '/approvals');
    expect(homeFor(UserRole.ceo), '/approvals');
    expect(homeFor(UserRole.superior), '/approvals');
    expect(homeFor(UserRole.employee), '/incharge');
  });
}
