import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/company.dart';
import 'package:rev_app/features/requests/domain/aging.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

FundRequest req(String id, String companyId,
        {RequestStatus status = RequestStatus.released}) =>
    FundRequest(
      id: id,
      companyId: companyId,
      fundId: 'f',
      createdByUid: 'u',
      beneficiaryName: 'B',
      amount: Money.fromCentavos(100),
      purpose: 'p',
      proofImageUrl: 'http://img',
      status: status,
    );

void main() {
  group('groupOutstandingByCompany', () {
    test('groups outstanding by company, one group per company with requests',
        () {
      final companies = [
        const Company(id: 'c1', name: 'Alpha'),
        const Company(id: 'c2', name: 'Bravo'),
      ];
      final outstanding = [req('r1', 'c1'), req('r2', 'c2'), req('r3', 'c1')];

      final groups = groupOutstandingByCompany(companies, outstanding);

      expect(groups.map((g) => g.company.id).toList(), ['c1', 'c2']);
      expect(groups[0].requests.map((r) => r.id).toList(), ['r1', 'r3']);
      expect(groups[1].requests.map((r) => r.id).toList(), ['r2']);
    });

    test('grouping is status-agnostic: released/acknowledged/disputed all group',
        () {
      final companies = [const Company(id: 'c1', name: 'Alpha')];
      final outstanding = [
        req('rel', 'c1', status: RequestStatus.released),
        req('ack', 'c1', status: RequestStatus.acknowledged),
        req('disp', 'c1', status: RequestStatus.disputed),
      ];

      final groups = groupOutstandingByCompany(companies, outstanding);

      expect(groups.length, 1);
      expect(groups.single.requests.map((r) => r.id).toList(),
          ['rel', 'ack', 'disp']);
    });

    test('sorts groups by company name, case-insensitive', () {
      final companies = [
        const Company(id: 'c1', name: 'zebra'),
        const Company(id: 'c2', name: 'Apple'),
        const Company(id: 'c3', name: 'mango'),
      ];
      final outstanding = [req('a', 'c1'), req('b', 'c2'), req('c', 'c3')];

      final groups = groupOutstandingByCompany(companies, outstanding);

      expect(groups.map((g) => g.company.name).toList(),
          ['Apple', 'mango', 'zebra']);
    });

    test('skips companies with zero outstanding requests', () {
      final companies = [
        const Company(id: 'c1', name: 'Alpha'),
        const Company(id: 'c2', name: 'Bravo'),
      ];
      final outstanding = [req('r1', 'c1')];

      final groups = groupOutstandingByCompany(companies, outstanding);

      expect(groups.length, 1);
      expect(groups.single.company.id, 'c1');
    });

    test('orphan requests go into an Unknown-company group placed last', () {
      final companies = [const Company(id: 'c1', name: 'Zeta')];
      final outstanding = [req('r1', 'c1'), req('orphan', 'ghost')];

      final groups = groupOutstandingByCompany(companies, outstanding);

      expect(groups.length, 2);
      expect(groups.last.company.id, '');
      expect(groups.last.company.name, 'Unknown company');
      expect(groups.last.requests.map((r) => r.id).toList(), ['orphan']);
    });

    test('preserves incoming request order within a group', () {
      final companies = [const Company(id: 'c1', name: 'Alpha')];
      final outstanding = [
        req('newest', 'c1'),
        req('older', 'c1'),
        req('oldest', 'c1')
      ];

      final groups = groupOutstandingByCompany(companies, outstanding);

      expect(groups.single.requests.map((r) => r.id).toList(),
          ['newest', 'older', 'oldest']);
    });

    test('empty outstanding yields no groups', () {
      final companies = [const Company(id: 'c1', name: 'Alpha')];
      expect(groupOutstandingByCompany(companies, const []), isEmpty);
    });
  });
}
