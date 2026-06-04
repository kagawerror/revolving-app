import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/fund.dart';
import '../domain/fund_repository.dart';

class FirestoreFundRepository implements FundRepository {
  final FirebaseFirestore _db;
  FirestoreFundRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('funds');

  @override
  Stream<List<Fund>> watchByCompany(String companyId) => _col
      .where('companyId', isEqualTo: companyId)
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map((d) => Fund.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<Fund>> watchAll() => _col
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map((d) => Fund.fromMap(d.id, d.data())).toList());

  @override
  Stream<Fund?> watchById(String fundId) => _col
      .doc(fundId)
      .snapshots()
      .map((d) => d.exists ? Fund.fromMap(d.id, d.data()!) : null);

  @override
  Future<Result<void>> create(Fund fund) async {
    try {
      await _col.add(fund.toCreateMap());
      return const Ok(null);
    } catch (e, st) {
      developer.log('create failed', name: 'funds', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not create the fund.'));
    }
  }
}
