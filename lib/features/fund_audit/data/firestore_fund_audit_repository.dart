import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../requests/domain/fund_request.dart';
import '../../requests/domain/request_status.dart';
import '../domain/fund_audit.dart';
import '../domain/fund_audit_repository.dart';

class FirestoreFundAuditRepository implements FundAuditRepository {
  final FirebaseFirestore _db;
  FirestoreFundAuditRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _audits =>
      _db.collection('fundAudits');
  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('requests');

  @override
  Future<Result<String>> create(FundAudit audit) async {
    try {
      final ref = await _audits.add(audit.toCreateMap());
      return Ok(ref.id);
    } catch (e, st) {
      developer.log('fund audit create failed',
          name: 'fund_audit', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not save the cash count.'));
    }
  }

  @override
  Future<Result<List<FundRequest>>> fetchOutstandingForFund(
    String companyId,
    String fundId,
  ) async {
    try {
      final snap = await _requests
          .where('companyId', isEqualTo: companyId)
          .where('fundId', isEqualTo: fundId)
          .where('status', whereIn: RequestStatus.outstandingStatusNames)
          .get();
      final requests =
          snap.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList();
      return Ok(requests);
    } catch (e, st) {
      developer.log('fetch outstanding for fund failed',
          name: 'fund_audit', error: e, stackTrace: st);
      return const Err(
          UnexpectedFailure('Could not load outstanding released cash.'));
    }
  }

  @override
  Future<Result<FundAudit>> getById(String id) async {
    try {
      final snap = await _audits.doc(id).get();
      final data = snap.data();
      if (!snap.exists || data == null) {
        return const Err(NotFoundFailure('Cash count not found.'));
      }
      return Ok(FundAudit.fromMap(snap.id, data));
    } catch (e, st) {
      developer.log('fund audit getById failed',
          name: 'fund_audit', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not load the cash count.'));
    }
  }

  @override
  Stream<List<FundAudit>> watchByFund(String companyId, String fundId) => _audits
      .where('companyId', isEqualTo: companyId)
      .where('fundId', isEqualTo: fundId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => FundAudit.fromMap(d.id, d.data())).toList());
}
