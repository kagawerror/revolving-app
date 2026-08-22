import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/company.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/companies/presentation/fund_grouping.dart';

Fund _fund({required String id, required String companyId, required String name}) =>
    Fund(
      id: id,
      companyId: companyId,
      name: name,
      originalBudget: Money.fromCentavos(1000000),
      availableBalance: Money.fromCentavos(500000),
      lowBalanceThresholdPct: 3,
      status: FundStatus.active,
    );

const _acme = Company(id: 'acme', name: 'Acme');
const _globex = Company(id: 'globex', name: 'Globex');

void main() {
  test('empty funds yields no groups', () {
    expect(groupFundsByCompany(const [], const [_acme, _globex]), isEmpty);
  });

  test('funds across two companies yield two groups sorted by company name', () {
    final funds = [
      _fund(id: 'g1', companyId: 'globex', name: 'Travel'),
      _fund(id: 'a1', companyId: 'acme', name: 'Petty cash'),
    ];
    final groups = groupFundsByCompany(funds, const [_acme, _globex]);

    expect(groups.map((g) => g.companyName).toList(), ['Acme', 'Globex']);
    expect(groups.first.funds.single.id, 'a1');
    expect(groups.last.funds.single.id, 'g1');
  });

  test('fund with unknown companyId lands in Unknown company group placed last',
      () {
    final funds = [
      _fund(id: 'x1', companyId: 'ghost', name: 'Orphan'),
      _fund(id: 'a1', companyId: 'acme', name: 'Petty cash'),
    ];
    final groups = groupFundsByCompany(funds, const [_acme]);

    expect(groups.map((g) => g.companyName).toList(), ['Acme', 'Unknown company']);
    expect(groups.last.funds.single.id, 'x1');
  });

  test('companies with zero funds are omitted', () {
    final funds = [_fund(id: 'a1', companyId: 'acme', name: 'Petty cash')];
    final groups = groupFundsByCompany(funds, const [_acme, _globex]);

    expect(groups.length, 1);
    expect(groups.single.companyName, 'Acme');
  });
}
