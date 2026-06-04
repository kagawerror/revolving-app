import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/auth/domain/auth_repository.dart';
import 'package:rev_app/features/profile/presentation/profile_controller.dart';

class _MockAuthRepo extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepo repo;
  setUp(() {
    repo = _MockAuthRepo();
    registerFallbackValue(ThemeMode.system);
  });

  test('setAccent persists via updateProfile(accentId:)', () async {
    when(() => repo.updateProfile(accentId: any(named: 'accentId')))
        .thenAnswer((_) async => const Ok(null));
    final c = ProfileController(repo);
    final res = await c.setAccent('violet');
    expect(res, isA<Ok<void>>());
    verify(() => repo.updateProfile(accentId: 'violet')).called(1);
  });
  test('setThemeMode persists via updateProfile(themeMode:)', () async {
    when(() => repo.updateProfile(themeMode: any(named: 'themeMode')))
        .thenAnswer((_) async => const Ok(null));
    final c = ProfileController(repo);
    await c.setThemeMode(ThemeMode.dark);
    verify(() => repo.updateProfile(themeMode: ThemeMode.dark)).called(1);
  });
  test('saveDisplayName trims and rejects empty', () async {
    final c = ProfileController(repo);
    final res = await c.saveDisplayName('   ');
    expect(res, isA<Err<void>>());
    verifyNever(() => repo.updateProfile(displayName: any(named: 'displayName')));
  });
}
