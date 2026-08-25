import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/reports/domain/report_period.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_repository.dart';

/// The Activity-history window used by every case below: June 2026, i.e.
/// `[2026-06-01 00:00, 2026-07-01 00:00)`.
final _june = periodWindow(PeriodGranularity.month, DateTime(2026, 6, 15));

/// The cursor a caller builds from the last row it rendered.
PeriodCursor _cursor(FundRequest r) => (at: r.createdAt!, id: r.id);

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreRequestRepository repo;

  // Explicit Timestamps (NOT serverTimestamp): the fake resolves
  // serverTimestamp lazily, which makes orderBy/range on createdAt unreliable.
  Future<void> seed(
    String id, {
    required String companyId,
    required DateTime createdAt,
    String status = 'released',
  }) =>
      db.collection('requests').doc(id).set({
        'companyId': companyId,
        'fundId': 'f',
        'createdByUid': 'u',
        'beneficiaryName': 'B',
        'amountCentavos': 100,
        'purpose': 'x',
        'proofImageUrl': 'http://img',
        'status': status,
        'replenishmentId': null,
        'createdAt': Timestamp.fromDate(createdAt),
      });

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreRequestRepository(db);
  });

  List<String> ids(List<FundRequest> list) => list.map((r) => r.id).toList();

  group('fetchByCompanyAndPeriod', () {
    test('scopes to the company and to the [start, endExclusive) window',
        () async {
      // Inside the window, own company.
      await seed('in-a', companyId: 'c1', createdAt: DateTime(2026, 6, 10));
      // Inside the window, OTHER company — must not leak across tenants.
      await seed('other', companyId: 'c2', createdAt: DateTime(2026, 6, 11));
      // Just before the window (May 31, 23:59) — excluded.
      await seed('before',
          companyId: 'c1', createdAt: DateTime(2026, 5, 31, 23, 59, 59));
      // Exactly the start boundary — INCLUDED (>=).
      await seed('start', companyId: 'c1', createdAt: DateTime(2026, 6, 1));
      // Exactly the end boundary — EXCLUDED (<).
      await seed('end', companyId: 'c1', createdAt: DateTime(2026, 7, 1));

      final result = await repo.fetchByCompanyAndPeriod(
        'c1',
        _june,
        limit: 50,
      );

      expect(result.isOk, isTrue);
      expect(ids(result.valueOrNull!), ['in-a', 'start']);
    });

    test('orders newest-first and respects the limit', () async {
      await seed('d1', companyId: 'c1', createdAt: DateTime(2026, 6, 1));
      await seed('d2', companyId: 'c1', createdAt: DateTime(2026, 6, 2));
      await seed('d3', companyId: 'c1', createdAt: DateTime(2026, 6, 3));
      await seed('d4', companyId: 'c1', createdAt: DateTime(2026, 6, 4));

      final result =
          await repo.fetchByCompanyAndPeriod('c1', _june, limit: 2);

      expect(ids(result.valueOrNull!), ['d4', 'd3']);
    });

    test('the `before` cursor pages forward with no overlap and no gap',
        () async {
      for (var day = 1; day <= 5; day++) {
        await seed('d$day', companyId: 'c1', createdAt: DateTime(2026, 6, day));
      }

      final page1 =
          await repo.fetchByCompanyAndPeriod('c1', _june, limit: 2);
      expect(ids(page1.valueOrNull!), ['d5', 'd4']);

      final page2 = await repo.fetchByCompanyAndPeriod(
        'c1',
        _june,
        limit: 2,
        before: _cursor(page1.valueOrNull!.last),
      );
      expect(ids(page2.valueOrNull!), ['d3', 'd2']);

      final page3 = await repo.fetchByCompanyAndPeriod(
        'c1',
        _june,
        limit: 2,
        before: _cursor(page2.valueOrNull!.last),
      );
      // Last page comes back SHORT of the limit — the "no more pages" signal.
      expect(ids(page3.valueOrNull!), ['d1']);
    });

    test(
        'requests sharing an identical createdAt still page without gaps or '
        'duplicates, even straddling a limit boundary', () async {
      // The offline outbox drains queued creates back-to-back on reconnect, so
      // identical server timestamps are realistic. 'tieA'/'tieB' collide on the
      // exact same instant AND fall either side of the limit-2 page boundary.
      await seed('newest', companyId: 'c1', createdAt: DateTime(2026, 6, 9));
      await seed('tieB', companyId: 'c1', createdAt: DateTime(2026, 6, 5));
      await seed('tieA', companyId: 'c1', createdAt: DateTime(2026, 6, 5));
      await seed('oldest', companyId: 'c1', createdAt: DateTime(2026, 6, 1));

      final seen = <String>[];
      PeriodCursor? cursor;
      for (var page = 0; page < 5; page++) {
        final result = await repo.fetchByCompanyAndPeriod(
          'c1',
          _june,
          limit: 2,
          before: cursor,
        );
        final rows = result.valueOrNull!;
        if (rows.isEmpty) break;
        seen.addAll(ids(rows));
        cursor = _cursor(rows.last);
      }

      // Every seeded request appears EXACTLY once across the walk.
      expect(seen, hasLength(4));
      expect(seen.toSet(), {'newest', 'tieB', 'tieA', 'oldest'});
      // Newest-first overall, with the tie broken deterministically.
      expect(seen.first, 'newest');
      expect(seen.last, 'oldest');
    });

    test('returns an empty page (not an error) when the window has no docs',
        () async {
      await seed('may', companyId: 'c1', createdAt: DateTime(2026, 5, 4));

      final result =
          await repo.fetchByCompanyAndPeriod('c1', _june, limit: 50);

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isEmpty);
    });
  });

  group('fetchAllByPeriod', () {
    test('spans every company but still honors the window', () async {
      await seed('a', companyId: 'c1', createdAt: DateTime(2026, 6, 10));
      await seed('b', companyId: 'c2', createdAt: DateTime(2026, 6, 20));
      await seed('c', companyId: 'c3', createdAt: DateTime(2026, 7, 1));

      final result = await repo.fetchAllByPeriod(_june, limit: 50);

      expect(ids(result.valueOrNull!), ['b', 'a']);
    });

    test('pages forward across companies with the `before` cursor', () async {
      await seed('a', companyId: 'c1', createdAt: DateTime(2026, 6, 1));
      await seed('b', companyId: 'c2', createdAt: DateTime(2026, 6, 2));
      await seed('c', companyId: 'c1', createdAt: DateTime(2026, 6, 3));

      final page1 = await repo.fetchAllByPeriod(_june, limit: 2);
      expect(ids(page1.valueOrNull!), ['c', 'b']);

      final page2 = await repo.fetchAllByPeriod(
        _june,
        limit: 2,
        before: _cursor(page1.valueOrNull!.last),
      );
      expect(ids(page2.valueOrNull!), ['a']);
    });
  });
}
