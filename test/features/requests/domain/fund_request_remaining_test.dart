import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

void main() {
  test('remaining = amount - replenished; defaults replenished to 0', () {
    final r = FundRequest.fromMap('r1', {
      'companyId': 'c1', 'fundId': 'f1', 'createdByUid': 'inc',
      'beneficiaryName': 'B', 'amountCentavos': 400000, 'purpose': 'x',
      'proofImageUrl': 'http://img', 'status': 'released', 'replenishmentId': null,
      // no replenishedCentavos -> legacy default 0
    });
    expect(r.replenished.centavos, 0);
    expect(r.remaining.centavos, 400000);
  });

  test('remaining shrinks by replenishedCentavos', () {
    final r = FundRequest.fromMap('r1', {
      'companyId': 'c1', 'fundId': 'f1', 'createdByUid': 'inc',
      'beneficiaryName': 'B', 'amountCentavos': 400000, 'purpose': 'x',
      'proofImageUrl': 'http://img', 'status': 'released',
      'replenishmentId': null, 'replenishedCentavos': 150000,
    });
    expect(r.replenished.centavos, 150000);
    expect(r.remaining.centavos, 250000);
  });

  test('toCreateMap writes replenishedCentavos: 0', () {
    final r = FundRequest(
      id: 'r1', companyId: 'c1', fundId: 'f1', createdByUid: 'inc',
      beneficiaryName: 'B', amount: Money.fromCentavos(400000), purpose: 'x',
      proofImageUrl: 'http://img', status: RequestStatus.released,
    );
    expect(r.toCreateMap()['replenishedCentavos'], 0);
  });
}
