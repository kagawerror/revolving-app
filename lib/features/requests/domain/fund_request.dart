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
  });

  bool get hasProof => proofImageUrl.isNotEmpty;

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
        'createdAt': FieldValue.serverTimestamp(),
      };

  @override
  List<Object?> get props => [
        id, companyId, fundId, createdByUid, beneficiaryName,
        amount, purpose, proofImageUrl, status, replenishmentId,
      ];
}
