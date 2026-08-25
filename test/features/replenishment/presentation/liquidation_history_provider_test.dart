import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/domain/liquidation_history.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_repository.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';
import 'package:rev_app/features/replenishment/presentation/replenishment_providers.dart';

class _MockReplenishmentRepository extends Mock
    implements ReplenishmentRepository {}

ReplenishmentItem _item(String requestId, int centavos,
        {bool isPartial = true}) =>
    ReplenishmentItem(
      requestId: requestId,
      isPartial: isPartial,
      amount: Money.fromCentavos(centavos),
    );

Replenishment _rep(
  String id,
  List<ReplenishmentItem> items, {
  ReplenishmentStatus status = ReplenishmentStatus.approved,
  DateTime? submittedAt,
}) =>
    Replenishment(
      id: id,
      companyId: 'c1',
      fundId: 'f1',
      status: status,
      requestIds: items.map((i) => i.requestId).toSet().toList(),
      total: Money.fromCentavos(items.fold(0, (s, i) => s + i.amount.centavos)),
      reportNotes: '',
      createdByUid: 'inc',
      items: items,
      submittedAt: submittedAt,
    );

void main() {
  late _MockReplenishmentRepository repo;

  setUp(() => repo = _MockReplenishmentRepository());

  ProviderContainer containerWith(List<Replenishment> reps) {
    when(() => repo.watchByRequestId(any(), any()))
        .thenAnswer((_) => Stream.value(reps));
    final c = ProviderContainer(overrides: [
      replenishmentRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('maps the repository stream into sorted liquidation entries', () async {
    final c = containerWith([
      _rep('rep2', [_item('reqA', 40000)],
          status: ReplenishmentStatus.submitted,
          submittedAt: DateTime.utc(2026, 3, 1)),
      _rep('rep1', [_item('reqA', 30000)],
          submittedAt: DateTime.utc(2026, 1, 1)),
      // Belongs to another request → must not appear.
      _rep('rep3', [_item('reqB', 99999)],
          submittedAt: DateTime.utc(2026, 2, 1)),
      // Draft → excluded by computeLiquidationHistory.
      _rep('rep4', [_item('reqA', 12345)],
          status: ReplenishmentStatus.draft,
          submittedAt: DateTime.utc(2026, 2, 2)),
      // Submitted FULL item → excluded (pendingPartial never subtracts it).
      _rep('rep5', [_item('reqA', 55555, isPartial: false)],
          status: ReplenishmentStatus.submitted,
          submittedAt: DateTime.utc(2026, 4, 1)),
    ]);

    final entries = await c.read(liquidationHistoryProvider(
      (companyId: 'c1', requestId: 'reqA'),
    ).future);

    expect(entries.map((e) => e.replenishmentId).toList(), ['rep1', 'rep2']);
    expect(entries.first.status, LiquidationEntryStatus.approved);
    expect(entries.first.amount.centavos, 30000);
    expect(entries.last.status, LiquidationEntryStatus.forApproval);
    expect(entries.last.isPartial, isTrue);
    expect(entries.last.amount.centavos, 40000);
  });

  test('queries the repository with the request\'s own companyId and id',
      () async {
    final c = containerWith(const []);

    await c.read(liquidationHistoryProvider(
      (companyId: 'c9', requestId: 'reqZ'),
    ).future);

    verify(() => repo.watchByRequestId('c9', 'reqZ')).called(1);
  });

  test('empty stream yields an empty history', () async {
    final c = containerWith(const []);

    final entries = await c.read(liquidationHistoryProvider(
      (companyId: 'c1', requestId: 'reqA'),
    ).future);

    expect(entries, isEmpty);
  });

  group('stream error', () {
    // This is the path that actually runs in production until the
    // (companyId, requestIds, createdAt) composite index is deployed —
    // Firestore answers FAILED_PRECONDITION.
    ProviderContainer erroringContainer(Object error) {
      when(() => repo.watchByRequestId(any(), any()))
          .thenAnswer((_) => Stream<List<Replenishment>>.error(error));
      final c = ProviderContainer(overrides: [
        replenishmentRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('surfaces AsyncError rather than hanging or silently resolving',
        () async {
      final c = erroringContainer(StateError('FAILED_PRECONDITION: index'));
      final provider = liquidationHistoryProvider(
        (companyId: 'c1', requestId: 'reqA'),
      );

      await expectLater(c.read(provider.future), throwsStateError);

      final state = c.read(provider);
      expect(state, isA<AsyncError<List<LiquidationEntry>>>());
      expect(state.hasError, isTrue);
      expect(state.error, isStateError);
      // The UI degrades to the lumped rows via valueOrNull, not a crash.
      expect(state.valueOrNull, isNull);
    });
  });
}
