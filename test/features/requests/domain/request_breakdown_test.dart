import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_breakdown.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

FundRequest _request({
  required int amountCentavos,
  int replenishedCentavos = 0,
  RequestStatus status = RequestStatus.released,
}) =>
    FundRequest(
      id: 'r1',
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'inc',
      beneficiaryName: 'B',
      amount: Money.fromCentavos(amountCentavos),
      purpose: 'x',
      proofImageUrl: 'http://img',
      status: status,
      replenishedCentavos: replenishedCentavos,
    );

void main() {
  group('computeRequestBreakdown', () {
    test('no partials → remaining = original, hasAnyPartial false', () {
      final b = computeRequestBreakdown(
        _request(amountCentavos: 3000000),
        pendingPartial: Money.zero,
      );
      expect(b.original.centavos, 3000000);
      expect(b.approvedPartial.centavos, 0);
      expect(b.pendingPartial.centavos, 0);
      expect(b.projectedRemaining.centavos, 3000000);
      expect(b.hasApproved, isFalse);
      expect(b.hasPending, isFalse);
      expect(b.hasAnyPartial, isFalse);
    });

    test('approved-only → remaining = original - approved', () {
      final b = computeRequestBreakdown(
        _request(amountCentavos: 3000000, replenishedCentavos: 1000000),
        pendingPartial: Money.zero,
      );
      expect(b.approvedPartial.centavos, 1000000);
      expect(b.pendingPartial.centavos, 0);
      expect(b.projectedRemaining.centavos, 2000000);
      expect(b.hasApproved, isTrue);
      expect(b.hasPending, isFalse);
      expect(b.hasAnyPartial, isTrue);
    });

    test('pending-only → 30k / 0 approved / 10k pending → 20k remaining', () {
      final b = computeRequestBreakdown(
        _request(amountCentavos: 3000000),
        pendingPartial: Money.fromCentavos(1000000),
      );
      expect(b.original.centavos, 3000000);
      expect(b.approvedPartial.centavos, 0);
      expect(b.pendingPartial.centavos, 1000000);
      expect(b.projectedRemaining.centavos, 2000000);
      expect(b.hasApproved, isFalse);
      expect(b.hasPending, isTrue);
      expect(b.hasAnyPartial, isTrue);
    });

    test('both → 30k / 10k approved / 10k pending → 10k remaining', () {
      final b = computeRequestBreakdown(
        _request(amountCentavos: 3000000, replenishedCentavos: 1000000),
        pendingPartial: Money.fromCentavos(1000000),
      );
      expect(b.original.centavos, 3000000);
      expect(b.approvedPartial.centavos, 1000000);
      expect(b.pendingPartial.centavos, 1000000);
      expect(b.projectedRemaining.centavos, 1000000);
      expect(b.hasAnyPartial, isTrue);
    });

    test('over-replenished → remaining floored at 0, never negative', () {
      final b = computeRequestBreakdown(
        _request(amountCentavos: 3000000, replenishedCentavos: 2000000),
        pendingPartial: Money.fromCentavos(2000000),
      );
      expect(b.original.centavos, 3000000);
      expect(b.approvedPartial.centavos, 2000000);
      expect(b.pendingPartial.centavos, 2000000);
      expect(b.projectedRemaining.centavos, 0);
    });
  });
}
