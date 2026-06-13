import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_repository.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/release_flow_controller.dart';
import 'package:rev_app/features/requests/presentation/request_providers.dart';
import 'package:rev_app/services/image/image_pick_compress.dart';

// Locks the "no Firestore write on cancel" guarantee for the release flow.
//
// `ReleaseFlowController.run` needs a real BuildContext (it shows a confirm
// dialog, pushes the signature screen, and drives snackbars), so it isn't
// testable from a bare ProviderContainer. The lightest seam that genuinely
// asserts `verifyNever(release)` is a minimal widget harness that pumps a
// button, taps it to invoke `run`, and overrides the pick/upload providers so
// each cancellation branch is reached deterministically — without changing any
// production code.
//
// Coverage here is the three *cancellation* branches, each fully driven by
// taps with no pad drawing required:
//   (a) confirm dialog cancelled,
//   (b) proof-photo pick returns null,
//   (c) signature screen cancelled (returns null).
// In every case `release()` must never run.
//
// The upload-failure branch (Err from the uploader) is intentionally NOT driven
// end-to-end through this harness: reaching it requires getting PAST the real
// SignatureCaptureScreen, which only pops non-null after rasterizing actual pad
// strokes to PNG bytes (`SignatureController.toPngBytes`). That is
// non-deterministic in a headless test and cannot be forced without weakening
// production code (e.g. injecting a fake signature screen). The upload-abort
// logic is a straight-line `valueOrNull == null -> return false` guard that
// runs before `release()`, identical in shape to the proof guard exercised in
// (b). See the controller's Step 4.

class _MockRepo extends Mock implements RequestRepository {}

class _MockPick extends Mock implements ImagePickCompress {}

FundRequest _request() => FundRequest(
      id: 'r1',
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: 'Ben',
      amount: Money.fromPesos(100),
      purpose: 'Lunch',
      proofImageUrl: 'https://cdn/p.jpg',
      status: RequestStatus.created,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_request());
  });

  /// Pumps a one-button app whose tap invokes `run(...)`. Overrides the pick
  /// provider so the proof-photo step is deterministic. The signature step uses
  /// the real SignatureCaptureScreen (we only ever cancel it).
  Future<ProviderContainer> pumpHarness(
    WidgetTester tester, {
    required _MockRepo repo,
    required _MockPick pick,
  }) async {
    final container = ProviderContainer(overrides: [
      requestRepositoryProvider.overrideWithValue(repo),
      imagePickCompressProvider.overrideWithValue(pick),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: ElevatedButton(
                  onPressed: () => ref
                      .read(releaseFlowControllerProvider.notifier)
                      .run(context, _request(), 'actor1'),
                  child: const Text('release'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('cancelling the confirm dialog never calls release',
      (tester) async {
    final repo = _MockRepo();
    final pick = _MockPick();
    // pick should not even be reached, but stub defensively.
    when(() => pick.pick(source: ImageSource.camera))
        .thenAnswer((_) async => null);

    await pumpHarness(tester, repo: repo, pick: pick);

    await tester.tap(find.text('release'));
    await tester.pumpAndSettle();
    expect(find.text('Release cash?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => repo.release(
          request: any(named: 'request'),
          actorUid: any(named: 'actorUid'),
          releaseProofUrl: any(named: 'releaseProofUrl'),
          releaseSignatureUrl: any(named: 'releaseSignatureUrl'),
          clientReleaseId: any(named: 'clientReleaseId'),
        ));
    expect(find.text('Release cancelled — no cash was deducted'),
        findsOneWidget);
  });

  testWidgets('cancelling the proof-photo pick never calls release',
      (tester) async {
    final repo = _MockRepo();
    final pick = _MockPick();
    when(() => pick.pick(source: ImageSource.camera))
        .thenAnswer((_) async => null); // user cancelled the camera.

    await pumpHarness(tester, repo: repo, pick: pick);

    await tester.tap(find.text('release'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue')); // past confirm.
    await tester.pumpAndSettle();

    verify(() => pick.pick(source: ImageSource.camera)).called(1);
    verifyNever(() => repo.release(
          request: any(named: 'request'),
          actorUid: any(named: 'actorUid'),
          releaseProofUrl: any(named: 'releaseProofUrl'),
          releaseSignatureUrl: any(named: 'releaseSignatureUrl'),
          clientReleaseId: any(named: 'clientReleaseId'),
        ));
    expect(find.text('Release cancelled — no cash was deducted'),
        findsOneWidget);
  });

  testWidgets('cancelling the signature screen never calls release',
      (tester) async {
    final repo = _MockRepo();
    final pick = _MockPick();
    when(() => pick.pick(source: ImageSource.camera))
        .thenAnswer((_) async => Uint8List.fromList([1, 2, 3])); // real proof.

    await pumpHarness(tester, repo: repo, pick: pick);

    await tester.tap(find.text('release'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue')); // past confirm.
    await tester.pumpAndSettle();

    // We are now on the SignatureCaptureScreen. Cancel it (its AppBar close
    // button pops null), which the controller treats as a cancellation.
    expect(find.text('Recipient Signature'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => repo.release(
          request: any(named: 'request'),
          actorUid: any(named: 'actorUid'),
          releaseProofUrl: any(named: 'releaseProofUrl'),
          releaseSignatureUrl: any(named: 'releaseSignatureUrl'),
          clientReleaseId: any(named: 'clientReleaseId'),
        ));
    expect(find.text('Release cancelled — no cash was deducted'),
        findsOneWidget);
  });
}
