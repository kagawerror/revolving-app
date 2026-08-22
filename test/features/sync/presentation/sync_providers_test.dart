import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/companies/domain/fund_repository.dart';
import 'package:rev_app/features/companies/presentation/admin_providers.dart';
import 'package:rev_app/features/sync/data/outbox_store.dart';
import 'package:rev_app/features/sync/domain/outbox_entry.dart';
import 'package:rev_app/features/sync/domain/release_intent.dart';
import 'package:rev_app/features/sync/domain/release_payload.dart';
import 'package:rev_app/features/sync/presentation/sync_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_app/core/error/result.dart';

class _FakeFundRepository implements FundRepository {
  _FakeFundRepository(this._fundsByCompany);
  final Map<String, Fund> _fundsByCompany;

  @override
  Stream<Fund?> watchById(String fundId) =>
      Stream<Fund?>.value(_fundsByCompany[fundId]);

  @override
  Stream<List<Fund>> watchAll() => const Stream.empty();
  @override
  Stream<List<Fund>> watchByCompany(String companyId) => const Stream.empty();
  @override
  Future<Result<void>> create(Fund fund) async => const Ok(null);
  @override
  Future<Result<void>> updateDetails({
    required String fundId,
    required String name,
    required int lowBalanceThresholdPct,
  }) async =>
      const Ok(null);
  @override
  Future<Result<void>> adjustBudget({
    required String fundId,
    required Money newBudget,
    required String actorUid,
    required String note,
  }) async =>
      const Ok(null);
  @override
  Future<Result<void>> adjustBalance({
    required String fundId,
    required int signedDeltaCentavos,
    required String reason,
    required String actorUid,
    required UserRole actorRole,
  }) async =>
      const Ok(null);
}

Fund _fund(String id, int balanceCentavos) => Fund(
      id: id,
      companyId: 'c1',
      name: 'Fund $id',
      originalBudget: Money.fromCentavos(1000000),
      availableBalance: Money.fromCentavos(balanceCentavos),
      lowBalanceThresholdPct: 3,
      status: FundStatus.active,
    );

OutboxEntry _releaseEntry(String id, String fundId, int amountCentavos) =>
    OutboxEntry(
      id: id,
      kind: OutboxKind.release,
      companyId: 'c1',
      entityId: 'req-$id',
      clientActionId: 'cai-$id',
      createdAtMillis: 1,
      payload: ReleasePayload.encode(ReleaseIntent(
        requestId: 'req-$id',
        fundId: fundId,
        companyId: 'c1',
        amount: Money.fromCentavos(amountCentavos),
        clientReleaseId: 'crid-$id',
      )),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer makeContainer({FundRepository? funds}) => ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          if (funds != null) fundRepositoryProvider.overrideWithValue(funds),
        ],
      );

  test('outboxStoreProvider resolves with the injected prefs', () {
    final c = makeContainer();
    addTearDown(c.dispose);
    expect(c.read(outboxStoreProvider), isA<OutboxStore>());
  });

  // Keeps the StreamProviders alive and lets pending microtasks (the
  // broadcast-stream emissions and Firestore-less fund stream) settle so the
  // synchronous derived providers see the latest snapshot.
  Future<void> settle(ProviderContainer c, List<ProviderListenable> keep) async {
    for (final p in keep) {
      c.listen(p, (prev, next) {}, fireImmediately: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  test('pendingReleaseIntentsProvider filters by fund and decodes', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final store = c.read(outboxStoreProvider);
    await store.enqueue(_releaseEntry('a', 'fundA', 5000));
    await store.enqueue(_releaseEntry('b', 'fundB', 9000));
    await store.enqueue(_releaseEntry('c', 'fundA', 1000));
    // A non-release entry must be ignored.
    await store.enqueue(OutboxEntry(
      id: 'd',
      kind: OutboxKind.transition,
      companyId: 'c1',
      entityId: 'x',
      clientActionId: 'k',
      createdAtMillis: 1,
    ));

    await settle(c, [outboxProvider]);

    final forA = c.read(pendingReleaseIntentsProvider('fundA'));
    expect(forA.map((i) => i.requestId), containsAll(['req-a', 'req-c']));
    expect(forA.length, 2);
  });

  test('done release entries are excluded from pending', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final store = c.read(outboxStoreProvider);
    await store.enqueue(_releaseEntry('a', 'fundA', 5000));
    await store.markDone('a');
    await settle(c, [outboxProvider]);
    expect(c.read(pendingReleaseIntentsProvider('fundA')), isEmpty);
  });

  test('optimisticFundBalanceProvider = server balance minus pending', () async {
    final funds = _FakeFundRepository({'fundA': _fund('fundA', 100000)});
    final c = makeContainer(funds: funds);
    addTearDown(c.dispose);
    final store = c.read(outboxStoreProvider);
    await store.enqueue(_releaseEntry('a', 'fundA', 30000));
    await store.enqueue(_releaseEntry('b', 'fundA', 25000));

    await settle(c, [outboxProvider, fundByIdProvider('fundA')]);

    final optimistic = c.read(optimisticFundBalanceProvider('fundA'));
    expect(optimistic.centavos, 100000 - 30000 - 25000); // 45000
    expect(optimistic.isNegative, isFalse);
  });

  test('optimistic balance goes negative on over-commitment', () async {
    final funds = _FakeFundRepository({'fundA': _fund('fundA', 10000)});
    final c = makeContainer(funds: funds);
    addTearDown(c.dispose);
    final store = c.read(outboxStoreProvider);
    await store.enqueue(_releaseEntry('a', 'fundA', 30000));
    await settle(c, [outboxProvider, fundByIdProvider('fundA')]);
    final optimistic = c.read(optimisticFundBalanceProvider('fundA'));
    expect(optimistic.centavos, 10000 - 30000); // -20000
    expect(optimistic.isNegative, isTrue);
  });

  test('absent fund falls back to zero server balance', () async {
    final funds = _FakeFundRepository({});
    final c = makeContainer(funds: funds);
    addTearDown(c.dispose);
    await settle(c, [fundByIdProvider('ghost')]);
    final optimistic = c.read(optimisticFundBalanceProvider('ghost'));
    expect(optimistic.centavos, 0);
  });
}
