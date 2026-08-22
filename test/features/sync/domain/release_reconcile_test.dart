import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/sync/domain/release_intent.dart';
import 'package:rev_app/features/sync/domain/release_reconcile.dart';

Fund _fund({
  required int balance,
  int budget = 100000,
  int thresholdPct = 10,
  FundStatus status = FundStatus.active,
}) =>
    Fund(
      id: 'f1',
      companyId: 'c1',
      name: 'Petty',
      originalBudget: Money.fromCentavos(budget),
      availableBalance: Money.fromCentavos(balance),
      lowBalanceThresholdPct: thresholdPct,
      status: status,
    );

ReleaseIntent _intent(int amount) => ReleaseIntent(
      requestId: 'r1',
      fundId: 'f1',
      companyId: 'c1',
      amount: Money.fromCentavos(amount),
      clientReleaseId: 'cid-1',
    );

void main() {
  group('reconcileRelease', () {
    test('alreadyApplied → no-op regardless of balance (idempotency)', () {
      final decision = reconcileRelease(
        _fund(balance: 0),
        _intent(5000),
        alreadyApplied: true,
      );
      expect(decision, const ReconcileAlreadyApplied());
    });

    test('sufficient balance → applied with deducted balance (not low)', () {
      // threshold = 10% of 100000 = 10000; new balance 47000 > 10000 → not low.
      final decision = reconcileRelease(
        _fund(balance: 50000, budget: 100000, thresholdPct: 10),
        _intent(3000),
        alreadyApplied: false,
      );
      expect(decision, ReconcileApplied(Money.fromCentavos(47000), false));
    });

    test('applied flags low when new balance crosses threshold', () {
      // threshold = 10% of 100000 = 10000; new balance 9000 <= 10000 → low.
      final decision = reconcileRelease(
        _fund(balance: 12000, budget: 100000, thresholdPct: 10),
        _intent(3000),
        alreadyApplied: false,
      );
      expect(decision, ReconcileApplied(Money.fromCentavos(9000), true));
    });

    test('two-device overdraft: insufficient → conflictInsufficient', () {
      // First device already drained the fund to 2000; this queued release for
      // 5000 can no longer be covered.
      final decision = reconcileRelease(
        _fund(balance: 2000),
        _intent(5000),
        alreadyApplied: false,
      );
      expect(decision, const ReconcileConflictInsufficient());
    });

    test('exactly-equal balance is releasable (boundary, not conflict)', () {
      final decision = reconcileRelease(
        _fund(balance: 5000, budget: 100000, thresholdPct: 0),
        _intent(5000),
        alreadyApplied: false,
      );
      expect(decision, const ReconcileApplied(Money.zero, true));
    });

    test('replenishing fund → conflictInsufficient even if balance covers', () {
      final decision = reconcileRelease(
        _fund(balance: 100000, status: FundStatus.replenishing),
        _intent(1000),
        alreadyApplied: false,
      );
      expect(decision, const ReconcileConflictInsufficient());
    });
  });
}
