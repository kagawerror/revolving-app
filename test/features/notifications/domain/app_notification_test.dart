import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/notifications/domain/app_notification.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_fill.dart';

void main() {
  test('fromMap parses + isUnread', () {
    final n = AppNotification.fromMap('n1', {
      'companyId': 'c1', 'recipientRoles': ['incharge'],
      'type': 'lowBalance', 'title': 'Low', 'body': 'Fund low', 'readAt': null,
    });
    expect(n.type, 'lowBalance');
    expect(n.recipientRoles, ['incharge']);
    expect(n.isUnread, isTrue);
  });

  test('isUnread is false when readAt is set', () {
    final n = AppNotification.fromMap('n2', {
      'companyId': 'c1', 'recipientRoles': ['incharge'],
      'type': 'lowBalance', 'title': 'L', 'body': 'b',
      'readAt': Timestamp.fromMillisecondsSinceEpoch(1000),
    });
    expect(n.isUnread, isFalse);
  });

  test('legacy map without denormalized keys → all-null getters', () {
    final n = AppNotification.fromMap('n3', {
      'companyId': 'c1', 'recipientRoles': ['incharge'],
      'type': 'lowBalance', 'title': 'L', 'body': 'b', 'readAt': null,
    });
    expect(n.fundName, isNull);
    expect(n.companyName, isNull);
    expect(n.actorName, isNull);
    expect(n.replenishAmount, isNull);
    expect(n.availableBalance, isNull);
    expect(n.fill, isNull);
    // New request-lifecycle getters are also null for a legacy doc.
    expect(n.requestId, isNull);
    expect(n.requestAmount, isNull);
    expect(n.requestPurpose, isNull);
    expect(n.requestBeneficiaryName, isNull);
    expect(n.originalAmount, isNull);
  });

  test('request-type map → request getters populated', () {
    final n = AppNotification.fromMap('n7', {
      'companyId': 'c1', 'recipientRoles': ['superior', 'manager', 'ceo'],
      'type': 'requestReleased', 'title': 'New release to review',
      'body': 'A cash release needs your review.', 'readAt': null,
      'requestId': 'req-1', 'requestAmountCentavos': 200000,
      'requestPurpose': 'Office supplies', 'requestBeneficiaryName': 'Ben',
      'fundName': 'Petty Cash',
    });
    expect(n.requestId, 'req-1');
    expect(n.requestAmount, Money.fromCentavos(200000));
    expect(n.requestPurpose, 'Office supplies');
    expect(n.requestBeneficiaryName, 'Ben');
    expect(n.fundName, 'Petty Cash');
    // Not a replenishment → no replenish hero / fill.
    expect(n.replenishAmount, isNull);
    expect(n.fill, isNull);
  });

  test('originalAmount round-trips from originalAmountCentavos', () {
    final n = AppNotification.fromMap('n8', {
      'companyId': 'c1', 'recipientRoles': ['incharge'],
      'type': 'replenishmentApproved', 'title': 'T', 'body': 'b',
      'replenishAmountCentavos': 100000, 'originalAmountCentavos': 250000,
      'fillType': 'partial',
    });
    expect(n.replenishAmount, Money.fromCentavos(100000));
    expect(n.originalAmount, Money.fromCentavos(250000));
  });

  test('full map → correct Money getters + fill enum', () {
    final n = AppNotification.fromMap('n4', {
      'companyId': 'c1', 'recipientRoles': ['superior', 'manager', 'ceo'],
      'type': 'replenishmentSubmitted', 'title': 'T', 'body': 'b', 'readAt': null,
      'fundName': 'Petty Cash', 'companyName': 'Acme', 'actorName': 'Ada',
      'replenishAmountCentavos': 800000, 'availableBalanceCentavos': 200000,
      'fillType': 'mixed', 'replenishmentId': 'rp1',
    });
    expect(n.fundName, 'Petty Cash');
    expect(n.companyName, 'Acme');
    expect(n.actorName, 'Ada');
    expect(n.replenishAmount, Money.fromCentavos(800000));
    expect(n.availableBalance, Money.fromCentavos(200000));
    expect(n.fill, ReplenishmentFill.mixed);
  });

  test('fill is null when fillType is null or garbage', () {
    final nNull = AppNotification.fromMap('n5', {
      'companyId': 'c1', 'recipientRoles': ['incharge'],
      'type': 'replenishmentApproved', 'title': 'T', 'body': 'b',
    });
    expect(nNull.fill, isNull);
    final nGarbage = AppNotification.fromMap('n6', {
      'companyId': 'c1', 'recipientRoles': ['incharge'],
      'type': 'replenishmentApproved', 'title': 'T', 'body': 'b',
      'fillType': 'nonsense',
    });
    expect(nGarbage.fill, isNull);
  });
}
