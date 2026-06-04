import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/theme/theme_controller.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';

void main() {
  group('themeStateForUser', () {
    test('null user -> brand default (system + forest seed)', () {
      final s = themeStateForUser(null);
      expect(s.mode, ThemeMode.system);
      expect(s.seed, const Color(0xFF0B6E4F));
    });
    test('user prefs drive mode + seed', () {
      final user = AppUser(
        uid: 'u',
        companyId: 'c',
        role: UserRole.incharge,
        displayName: 'A',
        email: 'a@x.com',
        themeMode: ThemeMode.dark,
        accentId: 'indigo',
      );
      final s = themeStateForUser(user);
      expect(s.mode, ThemeMode.dark);
      expect(s.seed, const Color(0xFF4F46E5));
    });
  });
}
