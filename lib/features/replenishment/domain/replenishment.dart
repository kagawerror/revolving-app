import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';
import 'replenishment_status.dart';

class Replenishment extends Equatable {
  final String id;
  final String companyId;
  final String fundId;
  final ReplenishmentStatus status;
  final List<String> requestIds;
  final Money total;
  final String reportNotes;
  final String createdByUid;
  final String? submittedByUid;
  final String? approvedByUid;

  const Replenishment({
    required this.id,
    required this.companyId,
    required this.fundId,
    required this.status,
    required this.requestIds,
    required this.total,
    required this.reportNotes,
    required this.createdByUid,
    this.submittedByUid,
    this.approvedByUid,
  });

  int get itemCount => requestIds.length;

  factory Replenishment.fromMap(String id, Map<String, dynamic> m) => Replenishment(
        id: id,
        companyId: (m['companyId'] ?? '') as String,
        fundId: (m['fundId'] ?? '') as String,
        status: ReplenishmentStatus.fromName(m['status'] as String?),
        requestIds: List<String>.from((m['requestIds'] ?? const []) as List),
        total: Money.fromCentavos((m['totalCentavos'] ?? 0) as int),
        reportNotes: (m['reportNotes'] ?? '') as String,
        createdByUid: (m['createdByUid'] ?? '') as String,
        submittedByUid: m['submittedByUid'] as String?,
        approvedByUid: m['approvedByUid'] as String?,
      );

  Map<String, dynamic> toCreateMap() => {
        'companyId': companyId,
        'fundId': fundId,
        'status': status.name,
        'requestIds': requestIds,
        'totalCentavos': total.centavos,
        'reportNotes': reportNotes,
        'createdByUid': createdByUid,
        'submittedByUid': null,
        'approvedByUid': null,
        'createdAt': FieldValue.serverTimestamp(),
      };

  @override
  List<Object?> get props =>
      [id, companyId, fundId, status, requestIds, total, reportNotes, createdByUid,
       submittedByUid, approvedByUid];
}
