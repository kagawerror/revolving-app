import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/domain/original_amount.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

FundRequest req(int amountCentavos, {int replenishedCentavos = 0}) =>
    FundRequest(
      id: 'r$amountCentavos$replenishedCentavos',
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: 'Ben',
      amount: Money.fromCentavos(amountCentavos),
      purpose: 'x',
      proofImageUrl: 'https://img/x.jpg',
      status: RequestStatus.released,
      replenishedCentavos: replenishedCentavos,
    );

void main() {
  test('empty selection sums to 0', () {
    expect(sumOriginalCentavos(const []), 0);
  });

  test('single request sums its remaining', () {
    expect(sumOriginalCentavos([req(200000)]), 200000);
  });

  test('multiple requests sum their remainings', () {
    expect(
      sumOriginalCentavos([req(200000), req(150000), req(50000)]),
      400000,
    );
  });

  test('uses remaining (outstanding) not raw amount when partially replenished',
      () {
    // 200000 amount with 50000 already returned → 150000 still outstanding.
    expect(
      sumOriginalCentavos([req(200000, replenishedCentavos: 50000)]),
      150000,
    );
  });
}
