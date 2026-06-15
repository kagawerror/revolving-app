import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';

void main() {
  test('fromMap parses fields', () {
    final r = Replenishment.fromMap('rp1', {
      'companyId': 'c1', 'fundId': 'f1', 'status': 'submitted',
      'requestIds': ['a', 'b'], 'totalCentavos': 300000,
      'reportNotes': 'June', 'createdByUid': 'u1',
    });
    expect(r.fundId, 'f1');
    expect(r.status, ReplenishmentStatus.submitted);
    expect(r.requestIds, ['a', 'b']);
    expect(r.total, Money.fromCentavos(300000));
  });
  test('fromMap parses a Timestamp createdAt', () {
    final ts = DateTime(2026, 6, 5, 14, 30);
    final r = Replenishment.fromMap('rp1', {
      'companyId': 'c1', 'fundId': 'f1', 'status': 'approved',
      'requestIds': ['a'], 'totalCentavos': 1000, 'reportNotes': '',
      'createdByUid': 'u1', 'createdAt': Timestamp.fromDate(ts),
    });
    expect(r.createdAt, ts);
  });
  test('fromMap tolerates a missing createdAt (null)', () {
    final r = Replenishment.fromMap('rp1', {
      'companyId': 'c1', 'fundId': 'f1', 'status': 'approved',
      'requestIds': ['a'], 'totalCentavos': 1000, 'reportNotes': '',
      'createdByUid': 'u1',
    });
    expect(r.createdAt, isNull);
  });
  test('fromMap reads submittedByName when present', () {
    final r = Replenishment.fromMap('rp1', {
      'companyId': 'c1', 'fundId': 'f1', 'status': 'submitted',
      'requestIds': ['a'], 'totalCentavos': 1000, 'reportNotes': '',
      'createdByUid': 'u1', 'submittedByName': 'Ada Incharge',
    });
    expect(r.submittedByName, 'Ada Incharge');
  });
  test('fromMap tolerates a missing submittedByName (legacy → null)', () {
    final r = Replenishment.fromMap('rp1', {
      'companyId': 'c1', 'fundId': 'f1', 'status': 'submitted',
      'requestIds': ['a'], 'totalCentavos': 1000, 'reportNotes': '',
      'createdByUid': 'u1',
    });
    expect(r.submittedByName, isNull);
  });
  test('toCreateMap seeds draft fields and omits id', () {
    final r = Replenishment(
      id: '', companyId: 'c1', fundId: 'f1', status: ReplenishmentStatus.draft,
      requestIds: const ['a'], total: Money.fromCentavos(1000), reportNotes: '',
      createdByUid: 'u1');
    final m = r.toCreateMap();
    expect(m.containsKey('id'), isFalse);
    expect(m['status'], 'draft');
    expect(m['totalCentavos'], 1000);
    expect(m['requestIds'], ['a']);
  });
}
