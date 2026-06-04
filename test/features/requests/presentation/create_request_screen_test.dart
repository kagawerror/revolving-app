import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/companies/presentation/admin_company_context_bar.dart';
import 'package:rev_app/features/companies/presentation/admin_providers.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_repository.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/create_request_screen.dart';
import 'package:rev_app/features/requests/presentation/request_providers.dart';
import 'package:rev_app/services/cloudinary/cloudinary_uploader.dart';
import 'package:rev_app/services/image/image_pick_compress.dart';

class _MockRepo extends Mock implements RequestRepository {}

class _MockUploader extends Mock implements CloudinaryUploader {}

class _MockPicker extends Mock implements ImagePickCompress {}

/// A valid 1x1 transparent PNG so the proof-photo preview ([Image.memory]) can
/// actually decode it — fake bytes throw "Invalid image data" during paint.
final _pngBytes = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, //
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 11, 73, 68, 65, 84, //
  120, 218, 99, 100, 248, 207, 80, 15, 0, 4, 133, 1, 128, 132, 169, 140, 33, //
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

const _admin = AppUser(
  uid: 'a1',
  // Admin has an empty companyId — scope comes from the in-session selection.
  companyId: '',
  role: UserRole.admin,
  displayName: 'Admin',
  email: 'admin@acme.test',
);

const _incharge = AppUser(
  uid: 'i1',
  companyId: 'acme',
  role: UserRole.incharge,
  displayName: 'Cara',
  email: 'cara@acme.test',
);

Fund _fund(String id, String companyId) => Fund(
      id: id,
      companyId: companyId,
      name: 'Petty Cash',
      originalBudget: Money.fromCentavos(1000000),
      availableBalance: Money.fromCentavos(500000),
      lowBalanceThresholdPct: 3,
      status: FundStatus.active,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(FundRequest(
      id: '',
      companyId: '',
      fundId: '',
      createdByUid: '',
      beneficiaryName: '',
      amount: Money.zero,
      purpose: '',
      proofImageUrl: '',
      status: RequestStatus.draft,
    ));
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(ImageSource.gallery);
  });

  late _MockRepo repo;
  late _MockUploader uploader;
  late _MockPicker picker;

  setUp(() {
    repo = _MockRepo();
    uploader = _MockUploader();
    picker = _MockPicker();
  });

  // The form is taller than the default 800x600 test viewport, so give it a
  // tall surface to keep every control on-screen and avoid scroll flakiness.
  Future<void> pumpTall(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(child);
    await tester.pumpAndSettle();
  }

  Widget harness({
    required AppUser user,
    String? adminActive,
    List<Fund> funds = const [],
  }) =>
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(user)),
          adminActiveCompanyProvider.overrideWith((ref) => adminActive),
          requestRepositoryProvider.overrideWithValue(repo),
          cloudinaryUploaderProvider.overrideWithValue(uploader),
          imagePickCompressProvider.overrideWithValue(picker),
          // companyFundsProvider is keyed by the resolved companyId; return the
          // funds regardless of key so the dropdown can populate.
          companyFundsProvider.overrideWith((ref, id) => Stream.value(funds)),
        ],
        child: const MaterialApp(home: CreateRequestScreen()),
      );

  testWidgets(
    'admin with a selected company submits the SELECTED companyId',
    (tester) async {
      when(() => picker.pick(source: any(named: 'source')))
          .thenAnswer((_) async => _pngBytes);
      when(() => uploader.uploadJpeg(any()))
          .thenAnswer((_) async => const Ok('https://cdn/p.jpg'));
      when(() => repo.create(any())).thenAnswer((_) async => const Ok('r1'));

      await pumpTall(
          tester,
          harness(
            user: _admin,
            adminActive: 'acme',
            funds: [_fund('f1', 'acme')],
          ));

      // Pick the fund from the dropdown.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Petty Cash').last);
      await tester.pumpAndSettle();

      // Fill the text fields.
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Beneficiary (employee)'), 'Ben');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount'), '10');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Purpose'), 'lunch');

      // Attach a proof photo via the (mocked) gallery picker.
      final gallery = find.widgetWithText(OutlinedButton, 'Gallery');
      await tester.ensureVisible(gallery);
      await tester.tap(gallery);
      await tester.pumpAndSettle();

      // Submit.
      final submit =
          find.widgetWithText(FilledButton, 'Send for acknowledgement');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      final captured =
          verify(() => repo.create(captureAny())).captured.single as FundRequest;
      expect(captured.companyId, 'acme');
      expect(captured.companyId, isNot(''));
      expect(captured.fundId, 'f1');
    },
  );

  testWidgets(
    'admin with no company selected is gated (no form, prompt shown)',
    (tester) async {
      await tester.pumpWidget(harness(
        user: _admin,
        adminActive: null,
        funds: const [],
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AdminSelectCompanyPrompt), findsOneWidget);
      // The form fields must not be present.
      expect(find.byType(TextFormField), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Send for acknowledgement'),
          findsNothing);
      verifyNever(() => repo.create(any()));
    },
  );

  testWidgets(
    'non-admin submits with its own pinned companyId',
    (tester) async {
      when(() => picker.pick(source: any(named: 'source')))
          .thenAnswer((_) async => _pngBytes);
      when(() => uploader.uploadJpeg(any()))
          .thenAnswer((_) async => const Ok('https://cdn/p.jpg'));
      when(() => repo.create(any())).thenAnswer((_) async => const Ok('r1'));

      await pumpTall(
          tester,
          harness(
            user: _incharge,
            funds: [_fund('f9', 'acme')],
          ));

      // No context prompt for a non-admin.
      expect(find.byType(AdminSelectCompanyPrompt), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Petty Cash').last);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Beneficiary (employee)'), 'Ben');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount'), '10');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Purpose'), 'lunch');

      final gallery = find.widgetWithText(OutlinedButton, 'Gallery');
      await tester.ensureVisible(gallery);
      await tester.tap(gallery);
      await tester.pumpAndSettle();

      final submit =
          find.widgetWithText(FilledButton, 'Send for acknowledgement');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      final captured =
          verify(() => repo.create(captureAny())).captured.single as FundRequest;
      expect(captured.companyId, 'acme');
      expect(captured.fundId, 'f9');
    },
  );
}
