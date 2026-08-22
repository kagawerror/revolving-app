import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

/// The rejection audit trio on [FundRequest]. Mirrors the existing dispute
/// trio: read-only fields stamped at rejection time, never written by
/// [FundRequest.toCreateMap], and absent on every legacy doc.
void main() {
  Map<String, dynamic> baseMap() => <String, dynamic>{
        'companyId': 'c1',
        'fundId': 'f1',
        'createdByUid': 'u1',
        'beneficiaryName': 'Ben',
        'amountCentavos': 200000,
        'purpose': 'x',
        'proofImageUrl': 'https://img/x.jpg',
        'status': 'created',
      };

  test('fromMap reads the rejection audit trio', () {
    // Local, not UTC: Timestamp.toDate() returns a local DateTime, so a UTC
    // literal would compare unequal on any machine off UTC.
    final at = DateTime(2026, 8, 22, 4, 30);
    final r = FundRequest.fromMap('r1', {
      ...baseMap(),
      'status': 'rejected',
      'rejectedReason': 'Created by mistake — duplicate of R-1042.',
      'rejectedByUid': 'incharge1',
      'rejectedAt': Timestamp.fromDate(at),
    });

    expect(r.rejectedReason, 'Created by mistake — duplicate of R-1042.');
    expect(r.rejectedByUid, 'incharge1');
    expect(r.rejectedAt, at);
  });

  test('legacy docs without the trio deserialize to nulls', () {
    final r = FundRequest.fromMap('r1', baseMap());

    expect(r.rejectedReason, isNull);
    expect(r.rejectedByUid, isNull);
    expect(r.rejectedAt, isNull);
  });

  test('toCreateMap never stamps the rejection trio', () {
    final r = FundRequest(
      id: 'r1',
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: 'Ben',
      amount: Money.fromCentavos(200000),
      purpose: 'x',
      proofImageUrl: 'https://img/x.jpg',
      status: RequestStatus.created,
      rejectedReason: 'should not be persisted at creation',
      rejectedByUid: 'incharge1',
    );

    final map = r.toCreateMap();
    expect(map.containsKey('rejectedReason'), isFalse);
    expect(map.containsKey('rejectedByUid'), isFalse);
    expect(map.containsKey('rejectedAt'), isFalse);
  });

  test('copyWith carries the rejection trio and it counts toward equality', () {
    final r = FundRequest.fromMap('r1', baseMap());
    final rejected = r.copyWith(
      status: RequestStatus.rejected,
      rejectedReason: 'Created by mistake — duplicate of R-1042.',
      rejectedByUid: 'incharge1',
    );

    expect(rejected.rejectedReason, 'Created by mistake — duplicate of R-1042.');
    expect(rejected.rejectedByUid, 'incharge1');
    expect(rejected, isNot(equals(r)));
  });
}
