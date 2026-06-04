import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/domain/auth_repository.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/profile/presentation/profile_screen.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

const _user = AppUser(
  uid: 'u1',
  companyId: 'acme',
  role: UserRole.incharge,
  displayName: 'Jane Doe',
  email: 'jane@acme.test',
  accentId: 'forest',
);

void main() {
  setUpAll(() {
    registerFallbackValue(ThemeMode.system);
  });

  late _MockAuthRepository repo;

  setUp(() {
    repo = _MockAuthRepository();
    when(() => repo.watchCurrentUser())
        .thenAnswer((_) => Stream.value(_user));
    when(() => repo.updateProfile(
          displayName: any(named: 'displayName'),
          photoUrl: any(named: 'photoUrl'),
          themeMode: any(named: 'themeMode'),
          accentId: any(named: 'accentId'),
        )).thenAnswer((_) async => const Ok(null));
  });

  Widget harness() => ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
        ],
        // Plain MaterialApp (no google_fonts theme) to avoid font loading.
        child: const MaterialApp(home: ProfileScreen()),
      );

  testWidgets('renders user identity, theme control and accent grid',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Jane Doe'), findsWidgets);
    expect(find.text('jane@acme.test'), findsOneWidget);
    expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
    // One swatch per accent option.
    expect(find.text('Incharge'), findsOneWidget);
  });

  testWidgets('tapping an accent swatch persists the selection',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Tap the "Indigo" accent (not the current "forest").
    final indigo = find.bySemanticsLabel('Indigo accent');
    expect(indigo, findsOneWidget);
    await tester.ensureVisible(indigo);
    await tester.pumpAndSettle();
    await tester.tap(indigo);
    await tester.pump();

    verify(() => repo.updateProfile(accentId: 'indigo')).called(1);
  });

  testWidgets('changing the theme mode persists the selection',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final dark = find.text('Dark');
    await tester.ensureVisible(dark);
    await tester.pumpAndSettle();
    await tester.tap(dark);
    await tester.pump();

    verify(() => repo.updateProfile(themeMode: ThemeMode.dark)).called(1);
  });
}
