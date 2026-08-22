import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/config/domain/cloudinary_config.dart';
import 'package:rev_app/features/config/domain/cloudinary_config_repository.dart';
import 'package:rev_app/features/config/presentation/cloudinary_config_screen.dart';
import 'package:rev_app/features/config/presentation/config_providers.dart';

class _MockRepo extends Mock implements CloudinaryConfigRepository {}

const _admin = AppUser(
  uid: 'admin-1',
  companyId: '',
  role: UserRole.admin,
  displayName: 'Admin',
  email: 'admin@acme.test',
);

/// A saved doc with valid (non-empty) cloudName + uploadPreset so the form
/// seeds with values that pass validation — the gate is reached without the
/// "Required" validators firing.
const _saved = CloudinaryConfig(
  cloudName: 'acme-cloud',
  uploadPreset: 'unsigned-preset',
);

void main() {
  setUpAll(() {
    registerFallbackValue(CloudinaryConfig.empty);
  });

  late _MockRepo repo;

  setUp(() {
    repo = _MockRepo();
    when(() => repo.upsert(any(), any())).thenAnswer((_) async => const Ok(null));
  });

  // The form is taller than the default 800x600 test viewport; give it a tall
  // surface so the Save button is reachable without scroll flakiness.
  Future<void> pumpTall(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_admin)),
          cloudinaryConfigRepositoryProvider.overrideWithValue(repo),
          // Render the data state directly with a saved doc; this also feeds
          // effectiveCloudinaryConfigProvider, which derives from this stream.
          cloudinaryConfigStreamProvider
              .overrideWith((ref) => Stream.value(_saved)),
        ],
        child: const MaterialApp(home: CloudinaryConfigScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    final save = find.widgetWithText(FilledButton, 'Save configuration');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'tapping Save then Cancel in the confirm dialog never calls upsert',
    (tester) async {
      await pumpTall(tester);

      await tapSave(tester);

      // Confirmation dialog is up.
      expect(find.text('Save Cloudinary configuration?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Dialog dismissed and nothing was written.
      expect(find.text('Save Cloudinary configuration?'), findsNothing);
      verifyNever(() => repo.upsert(any(), any()));
    },
  );

  testWidgets(
    'tapping Save then confirming Save calls upsert exactly once',
    (tester) async {
      await pumpTall(tester);

      await tapSave(tester);

      expect(find.text('Save Cloudinary configuration?'), findsOneWidget);

      // The confirm action is the FilledButton labelled "Save" in the dialog.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      verify(() => repo.upsert(any(), any())).called(1);
    },
  );
}
