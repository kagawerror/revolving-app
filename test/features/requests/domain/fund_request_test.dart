import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

void main() {
  test('fromMap parses centavos and status', () {
    final r = FundRequest.fromMap('r1', {
      'companyId': 'c1',
      'fundId': 'f1',
      'createdByUid': 'u1',
      'beneficiaryName': 'Ben',
      'amountCentavos': 250000,
      'purpose': 'Fuel',
      'proofImageUrl': 'https://img/x.jpg',
      'status': 'pendingAck',
    });
    expect(r.amount, Money.fromPesos(2500));
    expect(r.status, RequestStatus.pendingAck);
    expect(r.hasProof, isTrue);
  });

  test('hasProof is false when url empty', () {
    final r = FundRequest.fromMap('r1', {'proofImageUrl': '', 'amountCentavos': 1});
    expect(r.hasProof, isFalse);
  });
}
