import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/domain/request_repository.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/create_request_controller.dart';
import 'package:rev_app/features/requests/presentation/request_providers.dart';
import 'package:rev_app/services/cloudinary/cloudinary_uploader.dart';

class _MockRepo extends Mock implements RequestRepository {}

class _MockUploader extends Mock implements CloudinaryUploader {}

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
    // uploadJpeg(any()) takes a Uint8List, so mocktail needs a fallback for it.
    registerFallbackValue(Uint8List(0));
  });

  test('submit fails when no proof image attached', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ctrl = c.read(createRequestControllerProvider.notifier);
    final res = await ctrl.submit(
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiary: 'Ben',
      amount: Money.fromPesos(10),
      purpose: 'x',
      imageBytes: null,
    );
    expect(res.failureOrNull, isNotNull);
  });

  test('submit fails when amount is zero', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final res = await c.read(createRequestControllerProvider.notifier).submit(
          companyId: 'c1',
          fundId: 'f1',
          createdByUid: 'u1',
          beneficiary: 'Ben',
          amount: Money.zero,
          purpose: 'x',
          imageBytes: Uint8List.fromList([1, 2, 3]),
        );
    expect(res.failureOrNull, isNotNull);
  });

  test('submit uploads then creates as pendingAck', () async {
    final repo = _MockRepo();
    final uploader = _MockUploader();
    when(() => uploader.uploadJpeg(any()))
        .thenAnswer((_) async => const Ok('https://cdn/p.jpg'));
    when(() => repo.create(any())).thenAnswer((_) async => const Ok('r1'));

    final c = ProviderContainer(overrides: [
      requestRepositoryProvider.overrideWithValue(repo),
      cloudinaryUploaderProvider.overrideWithValue(uploader),
    ]);
    addTearDown(c.dispose);

    final res = await c.read(createRequestControllerProvider.notifier).submit(
          companyId: 'c1',
          fundId: 'f1',
          createdByUid: 'u1',
          beneficiary: 'Ben',
          amount: Money.fromPesos(10),
          purpose: 'x',
          imageBytes: Uint8List.fromList([1, 2, 3]),
        );
    expect(res.valueOrNull, 'r1');
    final captured =
        verify(() => repo.create(captureAny())).captured.single as FundRequest;
    expect(captured.status, RequestStatus.pendingAck);
    expect(captured.proofImageUrl, 'https://cdn/p.jpg');
  });
}
