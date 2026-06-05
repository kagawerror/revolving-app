import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';
import 'replenishment_status.dart';

/// One line of a replenishment report: a released request being replenished
/// either in full or by a partial amount (with remarks).
class ReplenishmentItem extends Equatable {
  final String requestId;
  final bool isPartial;
  final Money amount;
  final String remarks;

  const ReplenishmentItem({
    required this.requestId,
    required this.isPartial,
    required this.amount,
    this.remarks = '',
  });

  ReplenishmentItem copyWithAmount(int centavos) => ReplenishmentItem(
        requestId: requestId,
        isPartial: isPartial,
        amount: Money.fromCentavos(centavos),
        remarks: remarks,
      );

  factory ReplenishmentItem.fromMap(Map<String, dynamic> m) => ReplenishmentItem(
        requestId: (m['requestId'] ?? '') as String,
        isPartial: (m['isPartial'] ?? false) as bool,
        amount: Money.fromCentavos((m['amountCentavos'] ?? 0) as int),
        remarks: (m['remarks'] ?? '') as String,
      );

  Map<String, dynamic> toMap() => {
        'requestId': requestId,
        'isPartial': isPartial,
        'amountCentavos': amount.centavos,
        'remarks': remarks,
      };

  @override
  List<Object?> get props => [requestId, isPartial, amount, remarks];
}

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
  final List<ReplenishmentItem> items;
  final DateTime? createdAt;

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
    this.items = const [],
    this.createdAt,
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
        items: ((m['items'] ?? const []) as List)
            .map((e) => ReplenishmentItem.fromMap(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
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
        'items': items.map((i) => i.toMap()).toList(),
        'createdAt': FieldValue.serverTimestamp(),
      };

  @override
  List<Object?> get props =>
      [id, companyId, fundId, status, requestIds, total, reportNotes, createdByUid,
       submittedByUid, approvedByUid, items, createdAt];
}
