import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/requests/domain/visible_funds.dart';

Fund _fund(String id, {String companyId = 'c1', String name = 'Fund'}) => Fund(
      id: id,
      companyId: companyId,
      name: name,
      originalBudget: Money.fromCentavos(100000),
      availableBalance: Money.fromCentavos(100000),
      lowBalanceThresholdPct: 3,
      status: FundStatus.active,
    );

AppUser _user(UserRole role, {List<String> assigned = const []}) => AppUser(
      uid: 'u1',
      companyId: 'c1',
      companyIds: const ['c1', 'c2'],
      role: role,
      displayName: 'User',
      email: 'u@e.com',
      assignedFundIds: assigned,
    );

void main() {
  final f1 = _fund('f1', name: 'Alpha');
  final f2 = _fund('f2', name: 'Bravo');
  final f3 = _fund('f3', companyId: 'c2', name: 'Charlie');
  final candidates = [f1, f2, f3];

  group('resolveVisibleFunds — incharge (scoped)', () {
    test('keeps only assigned funds', () {
      final result = resolveVisibleFunds(
        _user(UserRole.incharge, assigned: ['f1', 'f3']),
        candidates,
      );
      expect(result.isAssignmentScoped, isTrue);
      expect(result.funds, [f1, f3]);
      expect(result.isEmptyState, isFalse);
    });

    test('preserves candidate input order, not assignment order', () {
      final result = resolveVisibleFunds(
        _user(UserRole.incharge, assigned: ['f3', 'f1']),
        candidates,
      );
      // f1 comes before f3 in candidates → output follows candidates.
      expect(result.funds, [f1, f3]);
    });

    test('empty assignment → empty list + isEmptyState (NO fallback)', () {
      final result = resolveVisibleFunds(
        _user(UserRole.incharge, assigned: const []),
        candidates,
      );
      expect(result.isAssignmentScoped, isTrue);
      expect(result.funds, isEmpty);
      expect(result.isEmptyState, isTrue);
    });

    test('assignment referencing a fund not in candidates is simply absent', () {
      final result = resolveVisibleFunds(
        _user(UserRole.incharge, assigned: ['f1', 'ghost']),
        candidates,
      );
      expect(result.funds, [f1]);
      expect(result.isEmptyState, isFalse);
    });

    test('retains funds spanning multiple companies', () {
      final result = resolveVisibleFunds(
        _user(UserRole.incharge, assigned: ['f1', 'f3']),
        candidates,
      );
      expect(result.funds.map((f) => f.companyId).toSet(), {'c1', 'c2'});
    });
  });

  group('resolveVisibleFunds — unscoped roles', () {
    for (final role in [UserRole.admin, UserRole.ceo, UserRole.manager, UserRole.superior]) {
      test('$role sees all candidates, not scoped, never empty-state', () {
        final result = resolveVisibleFunds(_user(role), candidates);
        expect(result.isAssignmentScoped, isFalse);
        expect(result.funds, candidates);
        expect(result.isEmptyState, isFalse);
      });
    }

    test('admin with empty candidates is not an empty-state', () {
      final result = resolveVisibleFunds(_user(UserRole.admin), const []);
      expect(result.isAssignmentScoped, isFalse);
      expect(result.isEmptyState, isFalse);
    });
  });
}
