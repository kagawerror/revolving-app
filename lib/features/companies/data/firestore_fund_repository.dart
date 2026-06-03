import 'package:cloud_firestore/cloud_firestore.dart';

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
  Stream<Fund?> watchById(String fundId) => _col.doc(fundId).snapshots().map(
        (d) => d.exists ? Fund.fromMap(d.id, d.data()!) : null,
      );

  @override
  Future<void> create(Fund fund) => _col.add(fund.toCreateMap());
}
