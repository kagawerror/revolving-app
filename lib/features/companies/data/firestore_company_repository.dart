import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
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
  Future<Result<Company>> getById(String id) async {
    try {
      final snap = await _col.doc(id).get();
      if (!snap.exists) {
        return const Err(NotFoundFailure('Company not found.'));
      }
      return Ok(Company.fromMap(snap.id, snap.data()!));
    } catch (e, st) {
      developer.log('getById failed', name: 'companies', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not load the company.'));
    }
  }

  @override
  Future<Result<String>> create(String name) async {
    try {
      final ref = await _col
          .add({'name': name, 'createdAt': FieldValue.serverTimestamp()});
      return Ok(ref.id);
    } catch (e, st) {
      developer.log('create failed', name: 'companies', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not create the company.'));
    }
  }

  // CODER: implement the real rename (and matching firestore.rules). Stub keeps
  // the build green for the presentation layer.
  @override
  Future<Result<void>> update(String id, String name) async {
    try {
      await _col.doc(id).update({'name': name});
      return const Ok(null);
    } catch (e, st) {
      developer.log('update failed', name: 'companies', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not update the company.'));
    }
  }
}
