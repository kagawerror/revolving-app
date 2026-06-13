import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/sync/domain/release_intent.dart';

void main() {
  test('ReleaseIntent value equality by all fields', () {
    final a = ReleaseIntent(
      requestId: 'r1',
      fundId: 'f1',
      companyId: 'c1',
      amount: Money.fromCentavos(5000),
      clientReleaseId: 'cid',
      localProofPath: '/p.jpg',
      localSignaturePath: '/s.jpg',
    );
    final b = ReleaseIntent(
      requestId: 'r1',
      fundId: 'f1',
      companyId: 'c1',
      amount: Money.fromCentavos(5000),
      clientReleaseId: 'cid',
      localProofPath: '/p.jpg',
      localSignaturePath: '/s.jpg',
    );
    final c = b.copyAmount(Money.fromCentavos(1));
    expect(a, b);
    expect(a == c, isFalse);
  });
}

extension on ReleaseIntent {
  ReleaseIntent copyAmount(Money m) => ReleaseIntent(
        requestId: requestId,
        fundId: fundId,
        companyId: companyId,
        amount: m,
        clientReleaseId: clientReleaseId,
        localProofPath: localProofPath,
        localSignaturePath: localSignaturePath,
      );
}
