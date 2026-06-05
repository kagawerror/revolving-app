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

  /// Centavos of this request's [amount] already returned to the fund via
  /// replenishment (full or one-or-more partials). Default 0; legacy docs read
  /// as 0. The request closes (`replenished`) when a Full covers the remainder.
  final int replenishedCentavos;

  /// Server creation time. Null until the serverTimestamp materializes on the
  /// first server round-trip (and absent on legacy docs). Read-only: never set
  /// on create (toCreateMap uses FieldValue.serverTimestamp()).
  final DateTime? createdAt;

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
    this.replenishedCentavos = 0,
    this.createdAt,
  });

  bool get hasProof => proofImageUrl.isNotEmpty;

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
        replenishedCentavos: (m['replenishedCentavos'] ?? 0) as int,
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
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
      };

  @override
  List<Object?> get props => [
        id, companyId, fundId, createdByUid, beneficiaryName,
        amount, purpose, proofImageUrl, status, replenishmentId,
        replenishedCentavos, createdAt,
      ];
}
