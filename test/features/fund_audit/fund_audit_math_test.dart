import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/fund_audit/domain/denomination.dart';
import 'package:rev_app/features/fund_audit/domain/fund_audit_math.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

FundRequest _req({
  required int amountCentavos,
  int replenishedCentavos = 0,
  RequestStatus status = RequestStatus.released,
  String fundId = 'f1',
  String companyId = 'c1',
}) =>
    FundRequest(
      id: 'r',
      companyId: companyId,
      fundId: fundId,
      createdByUid: 'u',
      beneficiaryName: 'b',
      amount: Money.fromCentavos(amountCentavos),
      purpose: 'p',
      proofImageUrl: '',
      status: status,
      replenishedCentavos: replenishedCentavos,
    );

void main() {
  group('sumDenominations', () {
    test('empty map sums to zero', () {
      expect(sumDenominations(const {}), Money.zero);
    });

    test('one of each denomination sums to the exact total in centavos', () {
      final counts = {for (final d in Denomination.values) d: 1};
      // 1+5+10+25+100+500+1000+2000+5000+10000+20000+50000+100000
      const expected =
          1 + 5 + 10 + 25 + 100 + 500 + 1000 + 2000 + 5000 + 10000 + 20000 + 50000 + 100000;
      expect(sumDenominations(counts).centavos, expected);
    });

    test('respects 1-centavo and 1000-peso values with no double drift', () {
      final counts = {Denomination.c01: 3, Denomination.p1000: 7};
      expect(sumDenominations(counts).centavos, 3 * 1 + 7 * 100000);
    });

    test('large counts stay exact (no floating point)', () {
      final counts = {Denomination.c01: 999999};
      expect(sumDenominations(counts).centavos, 999999);
    });
  });

  group('outstandingReleasedCash', () {
    test('sums remaining across multiple released requests', () {
      final reqs = [
        _req(amountCentavos: 50000),
        _req(amountCentavos: 25000),
      ];
      expect(outstandingReleasedCash(reqs).centavos, 75000);
    });

    test('empty iterable is zero', () {
      expect(outstandingReleasedCash(const []), Money.zero);
    });

    test('nets partial replenishment — sums remaining (amount - replenished)',
        () {
      final reqs = [
        // 8000 released, 3000 already replenished → 5000 still out.
        _req(amountCentavos: 8000, replenishedCentavos: 3000),
        _req(amountCentavos: 10000),
      ];
      expect(outstandingReleasedCash(reqs).centavos, 15000);
    });

    test('counts release-first outstanding statuses (acknowledged, disputed)',
        () {
      // The repository pre-filters to these statuses; the math sums their
      // remaining the same way regardless of which outstanding status they hold.
      final reqs = [
        _req(amountCentavos: 4000, status: RequestStatus.released),
        _req(amountCentavos: 3000, status: RequestStatus.acknowledged),
        _req(amountCentavos: 2000, status: RequestStatus.disputed),
      ];
      expect(outstandingReleasedCash(reqs).centavos, 9000);
    });

    test('clamps a fully-replenished request to zero (never negative)', () {
      final reqs = [_req(amountCentavos: 5000, replenishedCentavos: 5000)];
      expect(outstandingReleasedCash(reqs).centavos, 0);
    });
  });

  group('computeFundAudit', () {
    test('balanced: physical + outstanding == budget → variance 0', () {
      final outcome = computeFundAudit(
        effectiveBudget: Money.fromCentavos(100000),
        counts: {Denomination.p100: 7}, // 70000 physical
        outstandingForFund: [_req(amountCentavos: 30000)],
      );
      expect(outcome.varianceCentavos, 0);
      expect(outcome.verdict, AuditVerdict.balanced);
      expect(outcome.physicalCash.centavos, 70000);
      expect(outcome.outstanding.centavos, 30000);
    });

    test('shortage: counted less than expected → positive signed variance', () {
      final outcome = computeFundAudit(
        effectiveBudget: Money.fromCentavos(100000),
        counts: {Denomination.p100: 5}, // 50000 physical
        outstandingForFund: [_req(amountCentavos: 30000)],
      );
      // 100000 - 50000 - 30000 = 20000 short
      expect(outcome.varianceCentavos, 20000);
      expect(outcome.verdict, AuditVerdict.shortage);
    });

    test('overage: counted more than expected → negative variance, never throws',
        () {
      final outcome = computeFundAudit(
        effectiveBudget: Money.fromCentavos(100000),
        counts: {Denomination.p1000: 1}, // 100000 physical
        outstandingForFund: [_req(amountCentavos: 30000)],
      );
      // 100000 - 100000 - 30000 = -30000 (overage), stays a signed int
      expect(outcome.varianceCentavos, -30000);
      expect(outcome.verdict, AuditVerdict.overage);
    });

    test('emits all 13 denomination rows in descending order', () {
      final outcome = computeFundAudit(
        effectiveBudget: Money.fromCentavos(0),
        counts: {Denomination.p50: 2},
        outstandingForFund: const [],
      );
      expect(outcome.denominations.length, 13);
      expect(outcome.denominations.first.denomination, Denomination.p1000);
      expect(outcome.denominations.last.denomination, Denomination.c01);
      final p50 = outcome.denominations
          .firstWhere((d) => d.denomination == Denomination.p50);
      expect(p50.count, 2);
      expect(p50.subtotalCentavos, 10000);
    });

    test('outstanding ignores non-outstanding-status requests when pre-filtered',
        () {
      // Caller pre-filters; passing only released requests here is the contract.
      final reqs = [
        _req(amountCentavos: 10000, status: RequestStatus.released),
      ];
      final outcome = computeFundAudit(
        effectiveBudget: Money.fromCentavos(10000),
        counts: const {},
        outstandingForFund: reqs,
      );
      expect(outcome.outstanding.centavos, 10000);
      expect(outcome.varianceCentavos, 0);
    });
  });
}
