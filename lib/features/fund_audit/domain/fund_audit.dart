import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';
import 'denomination.dart';
import 'denomination_count.dart';
import 'fund_audit_math.dart';

/// An immutable, dated record of a physical cash count (proof-of-cash) for one
/// fund. Once written it is never updated or deleted (enforced by Firestore
/// rules); a new count is always a new document.
///
/// [varianceCentavos] is a SIGNED raw int (positive = shortage, negative =
/// overage). All money amounts are stored as integer `*Centavos` fields.
class FundAudit extends Equatable {
  final String id;
  final String companyId;
  final String fundId;
  final String fundName;
  final String companyName;
  final String custodianUid;
  final String custodianName;
  final Money effectiveBudget;
  final Money physicalCash;
  final Money outstanding;
  final int varianceCentavos;
  final List<DenominationCount> denominations;
  final String proofImageUrl;
  final String note;
  final DateTime? createdAt;

  const FundAudit({
    required this.id,
    required this.companyId,
    required this.fundId,
    required this.fundName,
    required this.companyName,
    required this.custodianUid,
    required this.custodianName,
    required this.effectiveBudget,
    required this.physicalCash,
    required this.outstanding,
    required this.varianceCentavos,
    required this.denominations,
    required this.proofImageUrl,
    required this.note,
    this.createdAt,
  });

  AuditVerdict get verdict {
    if (varianceCentavos > 0) return AuditVerdict.shortage;
    if (varianceCentavos < 0) return AuditVerdict.overage;
    return AuditVerdict.balanced;
  }

  factory FundAudit.fromMap(String id, Map<String, dynamic> m) {
    final rawDenoms = (m['denominations'] as List<dynamic>?) ?? const [];
    final denominations = <DenominationCount>[
      for (final d in rawDenoms)
        if (d is Map)
          DenominationCount(
            denomination:
                DenominationX.fromName((d['denomination'] ?? '') as String?),
            count: (d['count'] ?? 0) as int,
          ),
    ];
    final ts = m['createdAt'];
    return FundAudit(
      id: id,
      companyId: (m['companyId'] ?? '') as String,
      fundId: (m['fundId'] ?? '') as String,
      fundName: (m['fundName'] ?? '') as String,
      companyName: (m['companyName'] ?? '') as String,
      custodianUid: (m['custodianUid'] ?? '') as String,
      custodianName: (m['custodianName'] ?? '') as String,
      effectiveBudget:
          Money.fromCentavos((m['effectiveBudgetCentavos'] ?? 0) as int),
      physicalCash: Money.fromCentavos((m['physicalCashCentavos'] ?? 0) as int),
      outstanding: Money.fromCentavos((m['outstandingCentavos'] ?? 0) as int),
      varianceCentavos: (m['varianceCentavos'] ?? 0) as int,
      denominations: denominations,
      proofImageUrl: (m['proofImageUrl'] ?? '') as String,
      note: (m['note'] ?? '') as String,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  /// Serializes for a write-once create. Stores all 13 denomination rows so the
  /// count grid round-trips exactly. `createdAt` is a server timestamp.
  Map<String, dynamic> toCreateMap() => {
        'companyId': companyId,
        'fundId': fundId,
        'fundName': fundName,
        'companyName': companyName,
        'custodianUid': custodianUid,
        'custodianName': custodianName,
        'effectiveBudgetCentavos': effectiveBudget.centavos,
        'physicalCashCentavos': physicalCash.centavos,
        'outstandingCentavos': outstanding.centavos,
        'varianceCentavos': varianceCentavos,
        'denominations': [
          for (final d in denominations)
            {'denomination': d.denomination.name, 'count': d.count},
        ],
        'proofImageUrl': proofImageUrl,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
      };

  @override
  List<Object?> get props => [
        id,
        companyId,
        fundId,
        fundName,
        companyName,
        custodianUid,
        custodianName,
        effectiveBudget,
        physicalCash,
        outstanding,
        varianceCentavos,
        denominations,
        proofImageUrl,
        note,
        createdAt,
      ];
}
