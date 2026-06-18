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

  /// Denormalized display name of the submitting incharge, stamped at submit
  /// time. Lets the approver's app (which writes the approved/rejected
  /// notifications) carry the submitter's name without reading the user doc.
  /// Null on drafts and legacy docs.
  final String? submittedByName;
  final String? approvedByUid;
  final List<ReplenishmentItem> items;
  final DateTime? createdAt;

  /// Server submit time, stamped when the draft is submitted for approval
  /// (`submittedAt: serverTimestamp()`). Null on drafts and legacy docs.
  /// Read-only: never set by [toCreateMap].
  final DateTime? submittedAt;

  /// Server decision time, stamped when an approver approves/rejects
  /// (`decidedAt: serverTimestamp()`). Null until decided and on legacy docs.
  /// Read-only: never set by [toCreateMap]. Used by the Reports feature as the
  /// approved-replenishment date.
  final DateTime? decidedAt;

  /// Sum of the selected requests' OUTSTANDING original amounts at submit time
  /// (the full owed total before any partial). Persisted so approve/reject can
  /// echo it back onto the incharge's outcome notification, where a partial
  /// hero is shown "of {original}". Null on drafts/legacy docs and full fills.
  final int? originalAmountCentavos;

  /// Rejection audit (approver action). Mirrors the requests dispute audit
  /// (`disputedReason`/`disputedByUid`/`disputedAt`). The [rejectionReason] is
  /// the required, user-facing explanation the incharge reads on the report's
  /// detail screen — it is PII and must NOT appear in any notification body.
  /// All null until the report is rejected, and on legacy docs. Read-only:
  /// never set by [toCreateMap] (set at rejection time, not creation).
  final String? rejectionReason;
  final String? rejectedByUid;
  final DateTime? rejectedAt;

  /// Acknowledgment audit (approver action on an auto-approved report). The
  /// report is already `approved` with the fund credited; acknowledge is a
  /// FIELD UPDATE (not a status transition) that records who/when an approver
  /// confirmed they saw it and clears the "Needs acknowledgment" badge. All
  /// null until acknowledged, and on legacy docs. Read-only: never set by
  /// [toCreateMap]. [acknowledgedByName] is a denormalized display name.
  final String? acknowledgedByUid;
  final String? acknowledgedByName;
  final DateTime? acknowledgedAt;

  /// True when this report was credited via the incharge's auto-approve submit
  /// (the new lifecycle), as opposed to a legacy approver approval. Drives the
  /// "needs acknowledgment" prompt. Null on drafts and legacy docs.
  final bool? autoApproved;

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
    this.submittedByName,
    this.approvedByUid,
    this.items = const [],
    this.createdAt,
    this.submittedAt,
    this.decidedAt,
    this.originalAmountCentavos,
    this.rejectionReason,
    this.rejectedByUid,
    this.rejectedAt,
    this.acknowledgedByUid,
    this.acknowledgedByName,
    this.acknowledgedAt,
    this.autoApproved,
  });

  int get itemCount => requestIds.length;

  /// True for an auto-approved report that an approver has not yet
  /// acknowledged. The fund is already credited; this only drives the
  /// "Needs acknowledgment" badge + the approver's single Acknowledge action.
  bool get needsAcknowledgment =>
      status == ReplenishmentStatus.approved &&
      (autoApproved ?? false) &&
      acknowledgedByUid == null;

  /// Original (pre-partial) total owed as [Money], or null when absent.
  Money? get originalTotal => originalAmountCentavos == null
      ? null
      : Money.fromCentavos(originalAmountCentavos!);

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
        submittedByName: m['submittedByName'] as String?,
        approvedByUid: m['approvedByUid'] as String?,
        items: ((m['items'] ?? const []) as List)
            .map((e) => ReplenishmentItem.fromMap(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
        submittedAt: (m['submittedAt'] as Timestamp?)?.toDate(),
        decidedAt: (m['decidedAt'] as Timestamp?)?.toDate(),
        originalAmountCentavos: m['originalAmountCentavos'] as int?,
        rejectionReason: m['rejectionReason'] as String?,
        rejectedByUid: m['rejectedByUid'] as String?,
        rejectedAt: (m['rejectedAt'] as Timestamp?)?.toDate(),
        acknowledgedByUid: m['acknowledgedByUid'] as String?,
        acknowledgedByName: m['acknowledgedByName'] as String?,
        acknowledgedAt: (m['acknowledgedAt'] as Timestamp?)?.toDate(),
        autoApproved: m['autoApproved'] as bool?,
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
       submittedByUid, submittedByName, approvedByUid, items, createdAt, submittedAt, decidedAt,
       originalAmountCentavos, rejectionReason, rejectedByUid, rejectedAt,
       acknowledgedByUid, acknowledgedByName, acknowledgedAt, autoApproved];
}
