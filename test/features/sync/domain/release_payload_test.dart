import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/sync/domain/release_intent.dart';
import 'package:rev_app/features/sync/domain/release_payload.dart';

void main() {
  final intent = ReleaseIntent(
    requestId: 'req1',
    fundId: 'fund1',
    companyId: 'c1',
    amount: Money.fromCentavos(150000),
    clientReleaseId: 'crid1',
    localProofPath: '/x/proof.jpg',
    localSignaturePath: '/x/sig.jpg',
  );

  test('encode then decode round-trips (money stays centavos)', () {
    final payload = ReleasePayload.encode(intent);
    expect(payload[ReleasePayload.kAmountCentavos], 150000);
    final back = ReleasePayload.decode(payload);
    expect(back, intent);
  });

  test('encode omits null image paths', () {
    final noImages = ReleaseIntent(
      requestId: 'r',
      fundId: 'f',
      companyId: 'c',
      amount: Money.fromCentavos(1),
      clientReleaseId: 'k',
    );
    final payload = ReleasePayload.encode(noImages);
    expect(payload.containsKey(ReleasePayload.kLocalProofPath), isFalse);
    expect(payload.containsKey(ReleasePayload.kLocalSignaturePath), isFalse);
    expect(ReleasePayload.decode(payload), noImages);
  });

  test('decode returns null on a malformed/non-release payload', () {
    expect(ReleasePayload.decode({}), isNull);
    expect(
      ReleasePayload.decode({
        ReleasePayload.kRequestId: 'r',
        ReleasePayload.kFundId: 'f',
        ReleasePayload.kCompanyId: 'c',
        ReleasePayload.kAmountCentavos: 'not-an-int',
        ReleasePayload.kClientReleaseId: 'k',
      }),
      isNull,
    );
  });
}
