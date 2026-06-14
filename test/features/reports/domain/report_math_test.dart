import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';
import 'package:rev_app/features/reports/domain/report_math.dart';
import 'package:rev_app/features/reports/domain/report_period.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

FundRequest req({
  required String id,
  int centavos = 10000,
  DateTime? releasedAt,
  DateTime? createdAt,
  RequestStatus status = RequestStatus.released,
  String beneficiaryName = 'Jane',
  String purpose = 'Fuel',
}) =>
    FundRequest(
      id: id,
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: beneficiaryName,
      amount: Money.fromCentavos(centavos),
      purpose: purpose,
      proofImageUrl: '',
      status: status,
      createdAt: createdAt,
      releasedAt: releasedAt,
    );

Replenishment rep({
  required String id,
  int centavos = 50000,
  ReplenishmentStatus status = ReplenishmentStatus.approved,
  DateTime? decidedAt,
  DateTime? createdAt,
  List<String> requestIds = const ['a', 'b'],
}) =>
    Replenishment(
      id: id,
      companyId: 'c1',
      fundId: 'f1',
      status: status,
      requestIds: requestIds,
      total: Money.fromCentavos(centavos),
      reportNotes: '',
      createdByUid: 'u1',
      createdAt: createdAt,
      decidedAt: decidedAt,
    );

void main() {
  final window = periodWindow(PeriodGranularity.month, DateTime(2026, 6, 10));

  group('releasedRowsInWindow', () {
    test('keeps releases inside the window, drops outside', () {
      final rows = releasedRowsInWindow([
        req(id: 'in', releasedAt: DateTime(2026, 6, 5)),
        req(id: 'before', releasedAt: DateTime(2026, 5, 31)),
        req(id: 'after', releasedAt: DateTime(2026, 7, 1)),
      ], window);
      expect(rows.map((r) => r.requestId), ['in']);
    });

    test('uses createdAt and flags datePending when releasedAt is null', () {
      final rows = releasedRowsInWindow([
        req(id: 'pending', releasedAt: null, createdAt: DateTime(2026, 6, 7)),
      ], window);
      expect(rows.single.datePending, isTrue);
      expect(rows.single.effectiveDate, DateTime(2026, 6, 7));
    });

    test('synced release is not datePending and uses releasedAt', () {
      final rows = releasedRowsInWindow([
        req(
          id: 'synced',
          releasedAt: DateTime(2026, 6, 8),
          createdAt: DateTime(2026, 6, 1),
        ),
      ], window);
      expect(rows.single.datePending, isFalse);
      expect(rows.single.effectiveDate, DateTime(2026, 6, 8));
    });

    test('status-agnostic: a later-replenished release still counts', () {
      final rows = releasedRowsInWindow([
        req(
          id: 'replenished',
          releasedAt: DateTime(2026, 6, 9),
          status: RequestStatus.replenished,
        ),
      ], window);
      expect(rows.map((r) => r.requestId), ['replenished']);
    });

    test('skips requests with neither timestamp', () {
      final rows = releasedRowsInWindow([
        req(id: 'nodate', releasedAt: null, createdAt: null),
      ], window);
      expect(rows, isEmpty);
    });

    test('sorts by effectiveDate descending', () {
      final rows = releasedRowsInWindow([
        req(id: 'early', releasedAt: DateTime(2026, 6, 2)),
        req(id: 'late', releasedAt: DateTime(2026, 6, 20)),
        req(id: 'mid', releasedAt: DateTime(2026, 6, 11)),
      ], window);
      expect(rows.map((r) => r.requestId), ['late', 'mid', 'early']);
    });
  });

  group('replenishmentRowsInWindow', () {
    test('approved only, inside window, by decidedAt', () {
      final rows = replenishmentRowsInWindow([
        rep(id: 'in', decidedAt: DateTime(2026, 6, 5)),
        rep(
          id: 'notApproved',
          status: ReplenishmentStatus.submitted,
          decidedAt: DateTime(2026, 6, 5),
        ),
        rep(id: 'outside', decidedAt: DateTime(2026, 7, 5)),
      ], window);
      expect(rows.map((r) => r.replenishmentId), ['in']);
    });

    test('falls back to createdAt when decidedAt absent', () {
      final rows = replenishmentRowsInWindow([
        rep(id: 'r', decidedAt: null, createdAt: DateTime(2026, 6, 4)),
      ], window);
      expect(rows.single.approvedDate, isNull);
      expect(rows.single.createdDate, DateTime(2026, 6, 4));
    });

    test('sorts descending and carries itemCount', () {
      final rows = replenishmentRowsInWindow([
        rep(id: 'early', decidedAt: DateTime(2026, 6, 2), requestIds: ['x']),
        rep(id: 'late', decidedAt: DateTime(2026, 6, 25), requestIds: ['x', 'y', 'z']),
      ], window);
      expect(rows.map((r) => r.replenishmentId), ['late', 'early']);
      expect(rows.first.itemCount, 3);
    });
  });

  group('grandTotal', () {
    test('empty is zero', () {
      expect(grandTotal(const []), Money.zero);
    });

    test('sums centavos', () {
      expect(
        grandTotal([Money.fromCentavos(150), Money.fromCentavos(2350)]),
        Money.fromCentavos(2500),
      );
    });
  });

  group('replenishmentLineRows', () {
    FundRequest reqL(String id, String name, String purpose, int cents) =>
        FundRequest(
          id: id, companyId: 'c', fundId: 'f1', createdByUid: 'u',
          beneficiaryName: name, amount: Money.fromCentavos(cents),
          purpose: purpose, proofImageUrl: 'http://x',
          status: RequestStatus.replenished,
        );

    Replenishment bundle(
            String id, DateTime decided, List<ReplenishmentItem> items) =>
        Replenishment(
          id: id, companyId: 'c', fundId: 'f1',
          status: ReplenishmentStatus.approved,
          requestIds: items.map((i) => i.requestId).toList(),
          total: items.fold(Money.zero, (a, i) => a + i.amount),
          reportNotes: '', createdByUid: 'u', items: items, decidedAt: decided,
        );

    test('one row per (bundle, item); enriches name/purpose/fund; full+partial',
        () {
      final requests = {
        'r1': reqL('r1', 'Alice', 'Laptop', 5000),
        'r2': reqL('r2', 'Bob', 'Load', 1000),
      };
      final funds = {'f1': 'AUDIT'};
      final reps = [
        bundle('rep1', DateTime(2026, 6, 10), [
          ReplenishmentItem(
              requestId: 'r1',
              isPartial: false,
              amount: Money.fromCentavos(5000)),
          ReplenishmentItem(
              requestId: 'r2',
              isPartial: true,
              amount: Money.fromCentavos(400),
              remarks: 'first'),
        ]),
      ];

      final rows = replenishmentLineRows(reps, requests, funds);

      expect(rows.length, 2);
      expect(rows.map((r) => r.beneficiaryName).toSet(), {'Alice', 'Bob'});
      final alice = rows.firstWhere((r) => r.beneficiaryName == 'Alice');
      expect(alice.fundName, 'AUDIT');
      expect(alice.isPartial, isFalse);
      expect(alice.amount.centavos, 5000);
      expect(alice.replenishmentId, 'rep1');
      final bob = rows.firstWhere((r) => r.beneficiaryName == 'Bob');
      expect(bob.isPartial, isTrue);
      expect(bob.remarks, 'first');
      expect(bob.amount.centavos, 400); // installment, not original 1000
    });

    test('skips items whose request cannot be resolved', () {
      final rows = replenishmentLineRows(
        [
          bundle('rep1', DateTime(2026, 6, 10), [
            ReplenishmentItem(
                requestId: 'ghost',
                isPartial: false,
                amount: Money.fromCentavos(500)),
          ])
        ],
        const {},
        {'f1': 'AUDIT'},
      );
      expect(rows, isEmpty);
    });

    test('sorted by approved date desc, then fund, then beneficiary', () {
      final requests = {
        'a': reqL('a', 'Zed', 'x', 100),
        'b': reqL('b', 'Amy', 'x', 100),
      };
      final rows = replenishmentLineRows([
        bundle('old', DateTime(2026, 6, 1), [
          ReplenishmentItem(
              requestId: 'a',
              isPartial: false,
              amount: Money.fromCentavos(100)),
        ]),
        bundle('new', DateTime(2026, 6, 9), [
          ReplenishmentItem(
              requestId: 'b',
              isPartial: false,
              amount: Money.fromCentavos(100)),
        ]),
      ], requests, {'f1': 'AUDIT'});
      expect(rows.first.replenishmentId, 'new'); // newer first
      expect(rows.last.replenishmentId, 'old');
    });

    test('grand total of rows equals the sum of bundle item amounts', () {
      final requests = {
        'r1': reqL('r1', 'A', 'x', 5000),
        'r2': reqL('r2', 'B', 'x', 1000)
      };
      final reps = [
        bundle('rep1', DateTime(2026, 6, 10), [
          ReplenishmentItem(
              requestId: 'r1',
              isPartial: false,
              amount: Money.fromCentavos(5000)),
          ReplenishmentItem(
              requestId: 'r2',
              isPartial: true,
              amount: Money.fromCentavos(400),
              remarks: 'x'),
        ]),
      ];
      final rows = replenishmentLineRows(reps, requests, {'f1': 'AUDIT'});
      expect(grandTotal(rows.map((r) => r.amount)).centavos, 5400);
    });
  });
}
