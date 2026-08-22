import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_auto_approve.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';

void main() {
  // Budget 1,000,000c; threshold 10% => low at/under 100,000c.
  Fund fundWith(int balanceCentavos) => Fund(
        id: 'f1',
        companyId: 'c1',
        name: 'PC',
        originalBudget: Money.fromCentavos(1000000),
        availableBalance: Money.fromCentavos(balanceCentavos),
        lowBalanceThresholdPct: 10,
        status: FundStatus.replenishing,
      );

  group('computeAutoApprove', () {
    test('normal credit lands well above the threshold -> active', () {
      final out = computeAutoApprove(fundWith(50000), Money.fromCentavos(300000));
      expect(out.newBalance.centavos, 350000);
      expect(out.newStatus, FundStatus.active);
    });

    test('credit that stays under the threshold -> low', () {
      // 10,000 + 50,000 = 60,000 <= 100,000 threshold.
      final out = computeAutoApprove(fundWith(10000), Money.fromCentavos(50000));
      expect(out.newBalance.centavos, 60000);
      expect(out.newStatus, FundStatus.low);
    });

    test('exactly at the threshold boundary is still low (<=)', () {
      // 40,000 + 60,000 = 100,000 == threshold.
      final out = computeAutoApprove(fundWith(40000), Money.fromCentavos(60000));
      expect(out.newBalance.centavos, 100000);
      expect(out.newStatus, FundStatus.low);
    });

    test('one centavo over the threshold crosses to active', () {
      final out = computeAutoApprove(fundWith(40001), Money.fromCentavos(60000));
      expect(out.newBalance.centavos, 100001);
      expect(out.newStatus, FundStatus.active);
    });
  });

  group('canAcknowledge', () {
    Replenishment rep({
      required ReplenishmentStatus status,
      bool? autoApproved,
      String? acknowledgedByUid,
    }) =>
        Replenishment(
          id: 'r1',
          companyId: 'c1',
          fundId: 'f1',
          status: status,
          requestIds: const ['x'],
          total: Money.fromCentavos(100),
          reportNotes: '',
          createdByUid: 'inc',
          autoApproved: autoApproved,
          acknowledgedByUid: acknowledgedByUid,
        );

    test('approved + autoApproved + unacked -> true', () {
      expect(
          canAcknowledge(rep(
              status: ReplenishmentStatus.approved, autoApproved: true)),
          isTrue);
    });

    test('already acknowledged -> false', () {
      expect(
          canAcknowledge(rep(
              status: ReplenishmentStatus.approved,
              autoApproved: true,
              acknowledgedByUid: 'mgr')),
          isFalse);
    });

    test('legacy approved (autoApproved null) -> false', () {
      expect(canAcknowledge(rep(status: ReplenishmentStatus.approved)), isFalse);
    });

    test('submitted / draft / rejected -> false', () {
      for (final s in [
        ReplenishmentStatus.submitted,
        ReplenishmentStatus.draft,
        ReplenishmentStatus.rejected,
      ]) {
        expect(canAcknowledge(rep(status: s, autoApproved: true)), isFalse);
      }
    });

    test('matches the model getter', () {
      final r =
          rep(status: ReplenishmentStatus.approved, autoApproved: true);
      expect(canAcknowledge(r), r.needsAcknowledgment);
    });
  });
}
