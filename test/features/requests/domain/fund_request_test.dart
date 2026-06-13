import 'package:cloud_firestore/cloud_firestore.dart';
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
      'status': 'created',
    });
    expect(r.amount, Money.fromPesos(2500));
    expect(r.status, RequestStatus.created);
    expect(r.hasProof, isTrue);
  });

  test('legacy pendingAck status remaps to created on read', () {
    final r = FundRequest.fromMap('r1', {
      'amountCentavos': 1,
      'status': 'pendingAck',
    });
    expect(r.status, RequestStatus.created);
  });

  test('fromMap parses the new offline-first fields', () {
    final disputedTs = Timestamp.fromDate(DateTime(2026, 6, 6, 8));
    final r = FundRequest.fromMap('r1', {
      'amountCentavos': 1,
      'releaseState': 'localPending',
      'clientReleaseId': 'cid-9',
      'disputedReason': 'wrong amount',
      'disputedByUid': 'approver-1',
      'disputedAt': disputedTs,
      'pendingImageRef': 'local://proof.jpg',
    });
    expect(r.releaseState, 'localPending');
    expect(r.clientReleaseId, 'cid-9');
    expect(r.disputedReason, 'wrong amount');
    expect(r.disputedByUid, 'approver-1');
    expect(r.disputedAt, DateTime(2026, 6, 6, 8));
    expect(r.pendingImageRef, 'local://proof.jpg');
  });

  test('new offline-first fields default to null on legacy docs', () {
    final r = FundRequest.fromMap('r1', {'amountCentavos': 1});
    expect(r.releaseState, isNull);
    expect(r.clientReleaseId, isNull);
    expect(r.disputedReason, isNull);
    expect(r.disputedByUid, isNull);
    expect(r.disputedAt, isNull);
    expect(r.pendingImageRef, isNull);
  });

  test('toCreateMap includes pendingImageRef only when set', () {
    final withRef = FundRequest.fromMap('r1', {
      'amountCentavos': 1,
      'status': 'created',
      'pendingImageRef': 'local://x.jpg',
    });
    expect(withRef.toCreateMap()['pendingImageRef'], 'local://x.jpg');

    final without = FundRequest.fromMap('r1', {
      'amountCentavos': 1,
      'status': 'created',
    });
    expect(without.toCreateMap().containsKey('pendingImageRef'), isFalse);
  });

  test('hasProof is false when url empty', () {
    final r = FundRequest.fromMap('r1', {'proofImageUrl': '', 'amountCentavos': 1});
    expect(r.hasProof, isFalse);
  });

  test('fromMap parses createdAt from a Timestamp', () {
    final ts = Timestamp.fromDate(DateTime(2026, 6, 5, 9, 30));
    final r = FundRequest.fromMap('r1', {
      'amountCentavos': 1,
      'createdAt': ts,
    });
    expect(r.createdAt, DateTime(2026, 6, 5, 9, 30));
  });

  test('createdAt is null when absent', () {
    final r = FundRequest.fromMap('r1', {'amountCentavos': 1});
    expect(r.createdAt, isNull);
  });
}
