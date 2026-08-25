import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/domain/liquidation_history.dart';
import 'package:rev_app/features/replenishment/domain/pending_partials.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';

ReplenishmentItem _item(String requestId, int centavos,
        {bool isPartial = true, String remarks = ''}) =>
    ReplenishmentItem(
      requestId: requestId,
      isPartial: isPartial,
      amount: Money.fromCentavos(centavos),
      remarks: remarks,
    );

Replenishment _rep(
  String id,
  List<ReplenishmentItem> items, {
  ReplenishmentStatus status = ReplenishmentStatus.approved,
  DateTime? submittedAt,
  DateTime? decidedAt,
  DateTime? createdAt,
  List<String>? requestIds,
}) =>
    Replenishment(
      id: id,
      companyId: 'c1',
      fundId: 'f1',
      status: status,
      requestIds: requestIds ?? items.map((i) => i.requestId).toSet().toList(),
      total: Money.fromCentavos(items.fold(0, (s, i) => s + i.amount.centavos)),
      reportNotes: '',
      createdByUid: 'inc',
      items: items,
      createdAt: createdAt,
      submittedAt: submittedAt,
      decidedAt: decidedAt,
    );

void main() {
  test('empty input yields an empty history', () {
    expect(computeLiquidationHistory('reqA', const <Replenishment>[]), isEmpty);
  });

  test('maps an approved full and a submitted partial into two entries', () {
    final reps = [
      _rep('rep1', [_item('reqA', 30000, remarks: 'first tranche')],
          status: ReplenishmentStatus.approved,
          submittedAt: DateTime.utc(2026, 1, 5)),
      _rep('rep2', [_item('reqA', 120000, isPartial: false)],
          status: ReplenishmentStatus.approved,
          submittedAt: DateTime.utc(2026, 2, 9)),
      _rep('rep3', [_item('reqA', 5000)],
          status: ReplenishmentStatus.submitted,
          submittedAt: DateTime.utc(2026, 3, 9)),
    ];

    final history = computeLiquidationHistory('reqA', reps);

    expect(history, hasLength(3));
    expect(history.first.replenishmentId, 'rep1');
    expect(history.first.isPartial, isTrue);
    expect(history.first.amount.centavos, 30000);
    expect(history.first.status, LiquidationEntryStatus.approved);
    expect(history.first.isApproved, isTrue);
    expect(history.first.remarks, 'first tranche');
    expect(history.first.date, DateTime.utc(2026, 1, 5));

    expect(history[1].replenishmentId, 'rep2');
    expect(history[1].isPartial, isFalse);
    expect(history[1].amount.centavos, 120000);
    expect(history[1].status, LiquidationEntryStatus.approved);

    expect(history.last.replenishmentId, 'rep3');
    expect(history.last.isPartial, isTrue);
    expect(history.last.amount.centavos, 5000);
    expect(history.last.status, LiquidationEntryStatus.forApproval);
    expect(history.last.isApproved, isFalse);
  });

  group('pending FULL items are excluded (ledger arithmetic)', () {
    test('a submitted FULL item emits no entry', () {
      // partialAmountByRequest skips non-partial items, so pendingPartial —
      // and therefore projectedRemaining — never subtracts this amount. If we
      // rendered a row for it, Original − Σ(rows) would not equal Remaining.
      final reps = [
        _rep('rep1', [_item('reqA', 120000, isPartial: false)],
            status: ReplenishmentStatus.submitted,
            submittedAt: DateTime.utc(2026, 2, 9)),
      ];

      expect(computeLiquidationHistory('reqA', reps), isEmpty);
    });

    test('a submitted PARTIAL item still emits an entry', () {
      final reps = [
        _rep('rep1', [_item('reqA', 40000)],
            status: ReplenishmentStatus.submitted,
            submittedAt: DateTime.utc(2026, 2, 9)),
      ];

      final history = computeLiquidationHistory('reqA', reps);

      expect(history, hasLength(1));
      expect(history.single.isPartial, isTrue);
      expect(history.single.status, LiquidationEntryStatus.forApproval);
      expect(history.single.amount.centavos, 40000);
    });

    test('an APPROVED full item still emits an entry (unchanged)', () {
      // Approved full items DO bump replenishedCentavos server-side, so they
      // reconcile with breakdown.approvedPartial.
      final reps = [
        _rep('rep1', [_item('reqA', 120000, isPartial: false)],
            status: ReplenishmentStatus.approved,
            submittedAt: DateTime.utc(2026, 2, 9)),
      ];

      final history = computeLiquidationHistory('reqA', reps);

      expect(history, hasLength(1));
      expect(history.single.isPartial, isFalse);
      expect(history.single.status, LiquidationEntryStatus.approved);
      expect(history.single.amount.centavos, 120000);
    });

    test('a REJECTED full item still emits an entry when opted in', () {
      final reps = [
        _rep('rep1', [_item('reqA', 120000, isPartial: false)],
            status: ReplenishmentStatus.rejected,
            submittedAt: DateTime.utc(2026, 2, 9)),
      ];

      final history =
          computeLiquidationHistory('reqA', reps, includeRejected: true);

      expect(history, hasLength(1));
      expect(history.single.isPartial, isFalse);
      expect(history.single.status, LiquidationEntryStatus.rejected);
    });

    test('a submitted report mixing partial and full keeps only the partial',
        () {
      final reps = [
        _rep('rep1', [
          _item('reqA', 40000),
          _item('reqA', 120000, isPartial: false),
        ], status: ReplenishmentStatus.submitted, submittedAt: DateTime.utc(2026, 2, 9)),
      ];

      final history = computeLiquidationHistory('reqA', reps);

      expect(history, hasLength(1));
      expect(history.single.amount.centavos, 40000);
    });
  });

  test('items belonging to other requests are excluded', () {
    final reps = [
      _rep('rep1', [
        _item('reqA', 30000),
        _item('reqB', 50000),
      ], submittedAt: DateTime.utc(2026, 1, 5)),
    ];

    final history = computeLiquidationHistory('reqA', reps);

    expect(history, hasLength(1));
    expect(history.single.amount.centavos, 30000);
  });

  test('draft reports are always excluded', () {
    final reps = [
      _rep('rep1', [_item('reqA', 30000)],
          status: ReplenishmentStatus.draft, createdAt: DateTime.utc(2026, 1, 5)),
    ];

    expect(computeLiquidationHistory('reqA', reps), isEmpty);
    expect(computeLiquidationHistory('reqA', reps, includeRejected: true),
        isEmpty);
  });

  test('rejected reports are excluded by default and included on request', () {
    final reps = [
      _rep('rep1', [_item('reqA', 30000)],
          status: ReplenishmentStatus.rejected,
          submittedAt: DateTime.utc(2026, 1, 5)),
    ];

    expect(computeLiquidationHistory('reqA', reps), isEmpty);

    final withRejected =
        computeLiquidationHistory('reqA', reps, includeRejected: true);
    expect(withRejected, hasLength(1));
    expect(withRejected.single.status, LiquidationEntryStatus.rejected);
    expect(withRejected.single.isApproved, isFalse);
  });

  test('date precedence is submittedAt > decidedAt > createdAt', () {
    final reps = [
      _rep('rep1', [_item('reqA', 100)],
          submittedAt: DateTime.utc(2026, 1, 1),
          decidedAt: DateTime.utc(2026, 2, 2),
          createdAt: DateTime.utc(2026, 3, 3)),
    ];
    expect(computeLiquidationHistory('reqA', reps).single.date,
        DateTime.utc(2026, 1, 1));

    final noSubmitted = [
      _rep('rep1', [_item('reqA', 100)],
          decidedAt: DateTime.utc(2026, 2, 2),
          createdAt: DateTime.utc(2026, 3, 3)),
    ];
    expect(computeLiquidationHistory('reqA', noSubmitted).single.date,
        DateTime.utc(2026, 2, 2));

    final onlyCreated = [
      _rep('rep1', [_item('reqA', 100)], createdAt: DateTime.utc(2026, 3, 3)),
    ];
    expect(computeLiquidationHistory('reqA', onlyCreated).single.date,
        DateTime.utc(2026, 3, 3));
  });

  test('a legacy report with no timestamps at all yields a null date', () {
    final reps = [
      _rep('rep1', [_item('reqA', 100)]),
    ];
    expect(computeLiquidationHistory('reqA', reps).single.date, isNull);
  });

  test('sorts oldest-first, null dates last, tie-broken by replenishmentId',
      () {
    final reps = [
      _rep('repZ', [_item('reqA', 1)]), // no dates → last
      _rep('repC', [_item('reqA', 2)], submittedAt: DateTime.utc(2026, 3, 1)),
      _rep('repB', [_item('reqA', 3)], submittedAt: DateTime.utc(2026, 1, 1)),
      // Same instant as repB → tie-break by id ascending, so repB then repD.
      _rep('repD', [_item('reqA', 4)], submittedAt: DateTime.utc(2026, 1, 1)),
      _rep('repA', [_item('reqA', 5)]), // no dates → last, but before repZ
    ];

    final history = computeLiquidationHistory('reqA', reps);

    expect(history.map((e) => e.replenishmentId).toList(),
        ['repB', 'repD', 'repC', 'repA', 'repZ']);
  });

  test('requestIds contains the id but items has no matching element → nothing',
      () {
    // Legacy doc: tagged with the request but carrying no line items.
    final reps = [
      _rep('rep1', const <ReplenishmentItem>[],
          requestIds: const ['reqA'], submittedAt: DateTime.utc(2026, 1, 5)),
    ];

    expect(computeLiquidationHistory('reqA', reps), isEmpty);
  });

  test('duplicate items for the same request are not merged', () {
    final reps = [
      _rep('rep1', [
        _item('reqA', 10000),
        _item('reqA', 20000),
      ], submittedAt: DateTime.utc(2026, 1, 5)),
    ];

    final history = computeLiquidationHistory('reqA', reps);

    expect(history, hasLength(2));
    expect(history.map((e) => e.amount.centavos).toList(), [10000, 20000]);
  });

  test(
      'entry totals reconcile with the approved/pending split the breakdown '
      'uses', () {
    // Ledger identity: approved entries sum to what request.replenished would
    // carry, and for-approval entries to pendingPartialByRequestProvider's
    // figure for the same fixture data.
    final reps = [
      _rep('rep1', [_item('reqA', 30000)],
          status: ReplenishmentStatus.approved,
          submittedAt: DateTime.utc(2026, 1, 5)),
      _rep('rep2', [_item('reqA', 25000)],
          status: ReplenishmentStatus.approved,
          submittedAt: DateTime.utc(2026, 2, 5)),
      _rep('rep3', [_item('reqA', 40000)],
          status: ReplenishmentStatus.submitted,
          submittedAt: DateTime.utc(2026, 3, 5)),
      // Submitted FULL item: partialAmountByRequest ignores it, so the history
      // must ignore it too or the two figures drift apart.
      _rep('rep5', [_item('reqA', 77777, isPartial: false)],
          status: ReplenishmentStatus.submitted,
          submittedAt: DateTime.utc(2026, 3, 6)),
      _rep('rep4', [_item('reqA', 99999)],
          status: ReplenishmentStatus.draft,
          createdAt: DateTime.utc(2026, 4, 5)),
    ];

    final history = computeLiquidationHistory('reqA', reps);
    int sumOf(LiquidationEntryStatus s) => history
        .where((e) => e.status == s)
        .fold(0, (acc, e) => acc + e.amount.centavos);

    expect(sumOf(LiquidationEntryStatus.approved), 55000);
    expect(sumOf(LiquidationEntryStatus.forApproval), 40000);

    // The for-approval entries must sum to EXACTLY what feeds
    // breakdown.pendingPartial for the same reports.
    final pending = partialAmountByRequest(
        reps.where((r) => r.status == ReplenishmentStatus.submitted));
    expect(sumOf(LiquidationEntryStatus.forApproval),
        pending['reqA']!.centavos);
  });
}
