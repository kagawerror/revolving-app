import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/sync/data/outbox_store.dart';
import 'package:rev_app/features/sync/data/sync_engine.dart';
import 'package:rev_app/features/sync/domain/release_sync_result.dart';
import 'package:rev_app/features/sync/presentation/sync_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts drain() calls. Subclasses SyncEngine (concrete, not an interface) and
/// overrides only drain(); the collaborators are inert no-op fakes that drain
/// never reaches because we override it.
class _CountingSyncEngine extends SyncEngine {
  _CountingSyncEngine(SharedPreferences prefs)
      : super(
          outbox: OutboxStore(prefs),
          images: _NoopImages(),
          uploader: _NoopUploader(),
          requests: _NoopRequests(),
          actorUid: () => 'actor',
        );

  int drainCalls = 0;

  @override
  Future<SyncReport> drain() async {
    drainCalls++;
    return const SyncReport();
  }
}

class _NoopImages implements SyncImageStore {
  @override
  Future<void> deleteQuietly(String path) async {}
  @override
  Future<Result<List<int>>> read(String path) async => const Ok(<int>[]);
}

class _NoopUploader implements SyncUploader {
  @override
  Future<Result<String>> uploadProof(Uint8List bytes) async => const Ok('');
  @override
  Future<Result<String>> uploadSignature(Uint8List bytes) async =>
      const Ok('');
}

class _NoopRequests implements SyncRequestRepository {
  @override
  Future<Result<void>> backfillCreateImage({
    required String requestId,
    required String proofImageUrl,
  }) async =>
      const Ok(null);
  @override
  Future<Result<ReleaseSyncResult>> confirmPendingRelease({
    required FundRequest request,
    required String clientReleaseId,
    required String releaseProofUrl,
    required String releaseSignatureUrl,
    required String actorUid,
  }) async =>
      const Ok(ReleaseSyncResult.confirmed);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late _CountingSyncEngine engine;
  late StreamController<bool> connectivity;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    engine = _CountingSyncEngine(prefs);
    connectivity = StreamController<bool>.broadcast();
  });

  tearDown(() => connectivity.close());

  // Mounts a Consumer that calls wireSyncOnReconnect once, wiring the
  // connectivity listener for the widget's lifetime, with the sync engine and
  // connectivity stream overridden.
  Future<void> pumpWiring(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncEngineProvider.overrideWithValue(engine),
          connectivityProvider.overrideWith((ref) => connectivity.stream),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            wireSyncOnReconnect(ref);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('drains once on the false -> true connectivity edge',
      (tester) async {
    await pumpWiring(tester);
    expect(engine.drainCalls, 0);

    connectivity.add(false);
    await tester.pump();
    expect(engine.drainCalls, 0, reason: 'false (no prior) is not an edge');

    connectivity.add(true);
    await tester.pump();
    expect(engine.drainCalls, 1, reason: 'false -> true edge drains once');
  });

  testWidgets('does not drain on true -> false (going offline)',
      (tester) async {
    await pumpWiring(tester);
    connectivity.add(true);
    await tester.pump();
    expect(engine.drainCalls, 1);

    connectivity.add(false);
    await tester.pump();
    expect(engine.drainCalls, 1, reason: 'true -> false must not drain');
  });

  testWidgets('does not re-drain while staying online (true -> true)',
      (tester) async {
    await pumpWiring(tester);
    connectivity.add(true);
    await tester.pump();
    connectivity.add(true);
    await tester.pump();
    connectivity.add(true);
    await tester.pump();
    expect(engine.drainCalls, 1,
        reason: 'only the first false -> true edge drains');
  });

  testWidgets('drains again on each fresh offline -> online edge',
      (tester) async {
    await pumpWiring(tester);
    connectivity.add(true); // edge 1
    await tester.pump();
    connectivity.add(false); // offline
    await tester.pump();
    connectivity.add(true); // edge 2
    await tester.pump();
    expect(engine.drainCalls, 2);
  });
}
