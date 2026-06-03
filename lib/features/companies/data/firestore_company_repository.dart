import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/company.dart';
import '../domain/company_repository.dart';

class FirestoreCompanyRepository implements CompanyRepository {
  final FirebaseFirestore _db;
  FirestoreCompanyRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('companies');

  @override
  Stream<List<Company>> watchAll() => _col.orderBy('name').snapshots().map(
        (s) => s.docs.map((d) => Company.fromMap(d.id, d.data())).toList(),
      );

  @override
  Future<String> create(String name) async {
    final ref = await _col.add({'name': name, 'createdAt': FieldValue.serverTimestamp()});
    return ref.id;
  }
}
