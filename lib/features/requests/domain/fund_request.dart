import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';
import 'request_status.dart';

class FundRequest extends Equatable {
  final String id;
  final String companyId;
  final String fundId;
  final String createdByUid;
  final String beneficiaryName;
  final Money amount;
  final String purpose;
  final String proofImageUrl;
  final RequestStatus status;
  final String? replenishmentId;

  /// Captured at cash release: a proof photo of the handover and the recipient's
  /// signature image URL. Empty until release (and on legacy released docs).
  /// Both are immutable once set (enforced in firestore.rules). Never written
  /// by [toCreateMap] — they don't exist at creation time.
  final String releaseProofUrl;
  final String releaseSignatureUrl;

  /// Centavos of this request's [amount] already returned to the fund via
  /// replenishment (full or one-or-more partials). Default 0; legacy docs read
  /// as 0. The request closes (`replenished`) when a Full covers the remainder.
  final int replenishedCentavos;

  /// Server creation time. Null until the serverTimestamp materializes on the
  /// first server round-trip (and absent on legacy docs). Read-only: never set
  /// on create (toCreateMap uses FieldValue.serverTimestamp()).
  final DateTime? createdAt;

  /// Offline-first release bookkeeping. All nullable so existing/legacy docs
  /// (and online-only writes) deserialize unchanged.
  ///
  /// [releaseState]: 'localPending' (optimistic, not yet server-confirmed) ·
  /// 'serverConfirmed' · 'conflict' (server rejected the deduction). Null on
  /// docs that never went through the offline release path.
  final String? releaseState;

  /// Stable client id minted when this release was first created on-device, so
  /// a replay after reconnect is idempotent. Null for non-release docs.
  final String? clientReleaseId;

  /// Dispute audit (post-hoc approver action). Null unless disputed.
  final String? disputedReason;
  final String? disputedByUid;
  final DateTime? disputedAt;

  /// Local reference to an image captured offline that still needs uploading +
  /// backfilling once a connection returns. Null when no image is pending.
  final String? pendingImageRef;

  const FundRequest({
    required this.id,
    required this.companyId,
    required this.fundId,
    required this.createdByUid,
    required this.beneficiaryName,
    required this.amount,
    required this.purpose,
    required this.proofImageUrl,
    required this.status,
    this.replenishmentId,
    this.releaseProofUrl = '',
    this.releaseSignatureUrl = '',
    this.replenishedCentavos = 0,
    this.createdAt,
    this.releaseState,
    this.clientReleaseId,
    this.disputedReason,
    this.disputedByUid,
    this.disputedAt,
    this.pendingImageRef,
  });

  bool get hasProof => proofImageUrl.isNotEmpty;
  bool get hasReleaseProof => releaseProofUrl.isNotEmpty;
  bool get hasReleaseSignature => releaseSignatureUrl.isNotEmpty;

  Money get replenished => Money.fromCentavos(replenishedCentavos);

  /// Outstanding amount still owed back to the fund (amount − replenished).
  Money get remaining => amount - replenished;

  factory FundRequest.fromMap(String id, Map<String, dynamic> m) => FundRequest(
        id: id,
        companyId: (m['companyId'] ?? '') as String,
        fundId: (m['fundId'] ?? '') as String,
        createdByUid: (m['createdByUid'] ?? '') as String,
        beneficiaryName: (m['beneficiaryName'] ?? '') as String,
        amount: Money.fromCentavos((m['amountCentavos'] ?? 0) as int),
        purpose: (m['purpose'] ?? '') as String,
        proofImageUrl: (m['proofImageUrl'] ?? '') as String,
        status: RequestStatus.fromName(m['status'] as String?),
        replenishmentId: m['replenishmentId'] as String?,
        releaseProofUrl: (m['releaseProofUrl'] ?? '') as String,
        releaseSignatureUrl: (m['releaseSignatureUrl'] ?? '') as String,
        replenishedCentavos: (m['replenishedCentavos'] ?? 0) as int,
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
        releaseState: m['releaseState'] as String?,
        clientReleaseId: m['clientReleaseId'] as String?,
        disputedReason: m['disputedReason'] as String?,
        disputedByUid: m['disputedByUid'] as String?,
        disputedAt: (m['disputedAt'] as Timestamp?)?.toDate(),
        pendingImageRef: m['pendingImageRef'] as String?,
      );

  Map<String, dynamic> toCreateMap() => {
        'companyId': companyId,
        'fundId': fundId,
        'createdByUid': createdByUid,
        'beneficiaryName': beneficiaryName,
        'amountCentavos': amount.centavos,
        'purpose': purpose,
        'proofImageUrl': proofImageUrl,
        'status': status.name,
        'replenishmentId': null,
        'replenishedCentavos': 0,
        'createdAt': FieldValue.serverTimestamp(),
        // Offline create: the proof image may not be uploaded yet — carry a
        // local pending reference so the rule can accept an empty proofImageUrl
        // and the outbox can backfill the URL once a connection returns.
        if (pendingImageRef != null) 'pendingImageRef': pendingImageRef,
      };

  FundRequest copyWith({
    String? id,
    String? companyId,
    String? fundId,
    String? createdByUid,
    String? beneficiaryName,
    Money? amount,
    String? purpose,
    String? proofImageUrl,
    RequestStatus? status,
    String? replenishmentId,
    String? releaseProofUrl,
    String? releaseSignatureUrl,
    int? replenishedCentavos,
    DateTime? createdAt,
    String? releaseState,
    String? clientReleaseId,
    String? disputedReason,
    String? disputedByUid,
    DateTime? disputedAt,
    String? pendingImageRef,
  }) =>
      FundRequest(
        id: id ?? this.id,
        companyId: companyId ?? this.companyId,
        fundId: fundId ?? this.fundId,
        createdByUid: createdByUid ?? this.createdByUid,
        beneficiaryName: beneficiaryName ?? this.beneficiaryName,
        amount: amount ?? this.amount,
        purpose: purpose ?? this.purpose,
        proofImageUrl: proofImageUrl ?? this.proofImageUrl,
        status: status ?? this.status,
        replenishmentId: replenishmentId ?? this.replenishmentId,
        releaseProofUrl: releaseProofUrl ?? this.releaseProofUrl,
        releaseSignatureUrl: releaseSignatureUrl ?? this.releaseSignatureUrl,
        replenishedCentavos: replenishedCentavos ?? this.replenishedCentavos,
        createdAt: createdAt ?? this.createdAt,
        releaseState: releaseState ?? this.releaseState,
        clientReleaseId: clientReleaseId ?? this.clientReleaseId,
        disputedReason: disputedReason ?? this.disputedReason,
        disputedByUid: disputedByUid ?? this.disputedByUid,
        disputedAt: disputedAt ?? this.disputedAt,
        pendingImageRef: pendingImageRef ?? this.pendingImageRef,
      );

  @override
  List<Object?> get props => [
        id, companyId, fundId, createdByUid, beneficiaryName,
        amount, purpose, proofImageUrl, status, replenishmentId,
        releaseProofUrl, releaseSignatureUrl,
        replenishedCentavos, createdAt,
        releaseState, clientReleaseId,
        disputedReason, disputedByUid, disputedAt, pendingImageRef,
      ];
}
