import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/domain/aging.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

/// A fixed "today" so day counts are deterministic.
final _today = DateTime(2026, 6, 5);

/// Builds a request whose [createdAt] is [daysAgo] calendar days before
/// [_today] (null when [daysAgo] is null) with the given [amountCentavos].
FundRequest req(
  String id, {
  int? daysAgo,
  int amountCentavos = 100,
}) =>
    FundRequest(
      id: id,
      companyId: 'c1',
      fundId: 'f',
      createdByUid: 'u',
      beneficiaryName: 'B',
      amount: Money.fromCentavos(amountCentavos),
      purpose: 'p',
      proofImageUrl: 'http://img',
      status: RequestStatus.released,
      createdAt: daysAgo == null ? null : _today.subtract(Duration(days: daysAgo)),
    );

void main() {
  group('bracketFor4', () {
    test('0 days is d1to30', () => expect(bracketFor4(0), AgingBracket.d1to30));
    test('1 day is d1to30', () => expect(bracketFor4(1), AgingBracket.d1to30));
    test('30 days is d1to30', () => expect(bracketFor4(30), AgingBracket.d1to30));
    test('31 days is d31to60',
        () => expect(bracketFor4(31), AgingBracket.d31to60));
    test('60 days is d31to60',
        () => expect(bracketFor4(60), AgingBracket.d31to60));
    test('61 days is d61to90',
        () => expect(bracketFor4(61), AgingBracket.d61to90));
    test('90 days is d61to90',
        () => expect(bracketFor4(90), AgingBracket.d61to90));
    test('91 days is d90plus',
        () => expect(bracketFor4(91), AgingBracket.d90plus));
  });

  group('bracketLabel', () {
    test('d1to30', () => expect(bracketLabel(AgingBracket.d1to30), '1–30 days'));
    test('d31to60',
        () => expect(bracketLabel(AgingBracket.d31to60), '31–60 days'));
    test('d61to90',
        () => expect(bracketLabel(AgingBracket.d61to90), '61–90 days'));
    test('d90plus',
        () => expect(bracketLabel(AgingBracket.d90plus), '90+ days'));
  });

  group('sumAmounts', () {
    test('empty is zero', () {
      expect(sumAmounts(const <FundRequest>[]), Money.zero);
      expect(sumAmounts(const <FundRequest>[]).centavos, 0);
    });

    test('single item', () {
      expect(sumAmounts([req('a', amountCentavos: 250)]).centavos, 250);
    });

    test('[100, 250, 99] sums to 449 centavos (integer, no double)', () {
      final sum = sumAmounts([
        req('a', amountCentavos: 100),
        req('b', amountCentavos: 250),
        req('c', amountCentavos: 99),
      ]);
      expect(sum.centavos, 449);
    });
  });

  group('groupByDayBracket', () {
    test('empty input yields no groups', () {
      expect(groupByDayBracket(const <FundRequest>[], _today), isEmpty);
    });

    test('orders groups most-stale-first (d90plus first, d1to30 last)', () {
      final groups = groupByDayBracket(
        [
          req('fresh', daysAgo: 5),
          req('ancient', daysAgo: 120),
          req('mid', daysAgo: 45),
          req('old', daysAgo: 75),
        ],
        _today,
      );

      expect(
        groups.map((g) => g.bracket).toList(),
        [
          AgingBracket.d90plus,
          AgingBracket.d61to90,
          AgingBracket.d31to60,
          AgingBracket.d1to30,
        ],
      );
    });

    test('all-in-one-bracket yields exactly one group', () {
      final groups = groupByDayBracket(
        [req('a', daysAgo: 5), req('b', daysAgo: 10), req('c', daysAgo: 25)],
        _today,
      );

      expect(groups.length, 1);
      expect(groups.single.bracket, AgingBracket.d1to30);
      expect(groups.single.count, 3);
    });

    test('null createdAt lands in d1to30', () {
      final groups = groupByDayBracket([req('nodate', daysAgo: null)], _today);

      expect(groups.single.bracket, AgingBracket.d1to30);
      expect(groups.single.requests.single.id, 'nodate');
    });

    test('preserves request order within a bracket', () {
      final groups = groupByDayBracket(
        [
          req('first', daysAgo: 3),
          req('second', daysAgo: 28),
          req('third', daysAgo: 12),
        ],
        _today,
      );

      expect(groups.single.requests.map((r) => r.id).toList(),
          ['first', 'second', 'third']);
    });

    test('per-group total equals sumAmounts and count matches', () {
      final groups = groupByDayBracket(
        [
          req('a', daysAgo: 5, amountCentavos: 100),
          req('b', daysAgo: 10, amountCentavos: 250),
          req('c', daysAgo: 100, amountCentavos: 999),
        ],
        _today,
      );

      final d1to30 = groups.firstWhere((g) => g.bracket == AgingBracket.d1to30);
      final d90plus = groups.firstWhere((g) => g.bracket == AgingBracket.d90plus);

      expect(d1to30.count, 2);
      expect(d1to30.total.centavos, 350);
      expect(d1to30.total, sumAmounts(d1to30.requests));

      expect(d90plus.count, 1);
      expect(d90plus.total.centavos, 999);
      expect(d90plus.total, sumAmounts(d90plus.requests));
    });

    test('boundary days land in the correct bracket', () {
      final groups = groupByDayBracket(
        [
          req('d30', daysAgo: 30),
          req('d31', daysAgo: 31),
          req('d60', daysAgo: 60),
          req('d61', daysAgo: 61),
          req('d90', daysAgo: 90),
          req('d91', daysAgo: 91),
        ],
        _today,
      );

      AgingBracket bracketOf(String id) => groups
          .firstWhere((g) => g.requests.any((r) => r.id == id))
          .bracket;

      expect(bracketOf('d30'), AgingBracket.d1to30);
      expect(bracketOf('d31'), AgingBracket.d31to60);
      expect(bracketOf('d60'), AgingBracket.d31to60);
      expect(bracketOf('d61'), AgingBracket.d61to90);
      expect(bracketOf('d90'), AgingBracket.d61to90);
      expect(bracketOf('d91'), AgingBracket.d90plus);
    });

    test('skips empty brackets (only populated brackets appear)', () {
      final groups = groupByDayBracket(
        [req('a', daysAgo: 5), req('b', daysAgo: 100)],
        _today,
      );

      expect(groups.map((g) => g.bracket).toList(),
          [AgingBracket.d90plus, AgingBracket.d1to30]);
    });
  });
}
