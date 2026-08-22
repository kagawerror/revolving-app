import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';

enum FundStatus {
  active,
  low,
  replenishing;

  static FundStatus fromName(String? n) =>
      FundStatus.values.firstWhere((s) => s.name == n, orElse: () => FundStatus.active);
}

class Fund extends Equatable {
  final String id;
  final String companyId;
  final String name;
  final Money originalBudget;
  final Money availableBalance;
  final int lowBalanceThresholdPct;
  final FundStatus status;

  /// Signed running total of availability-only adjustments (the admin/CEO
  /// "add/deduct cash" path). CAN be negative. Kept as a raw int because
  /// `Money.fromCentavos` rejects negatives. Budget edits (`adjustBudget`) do
  /// NOT accumulate here.
  final int adjustmentsCentavos;

  const Fund({
    required this.id,
    required this.companyId,
    required this.name,
    required this.originalBudget,
    required this.availableBalance,
    required this.lowBalanceThresholdPct,
    required this.status,
    this.adjustmentsCentavos = 0,
  });

  Money get lowBalanceThreshold =>
      originalBudget.percentageOf(lowBalanceThresholdPct);

  /// Budget including accumulated adjustments — the "Total budget" shown to
  /// users. Always >= 0 (you cannot deduct more cash than exists).
  Money get effectiveBudget =>
      Money.fromCentavos(originalBudget.centavos + adjustmentsCentavos);

  bool get isLow => availableBalance <= lowBalanceThreshold;

  bool canRelease(Money amount) => availableBalance >= amount;

  factory Fund.fromMap(String id, Map<String, dynamic> m) => Fund(
        id: id,
        companyId: (m['companyId'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        originalBudget: Money.fromCentavos((m['originalBudgetCentavos'] ?? 0) as int),
        availableBalance:
            Money.fromCentavos((m['availableBalanceCentavos'] ?? 0) as int),
        lowBalanceThresholdPct: (m['lowBalanceThresholdPct'] ?? 3) as int,
        status: FundStatus.fromName(m['status'] as String?),
        adjustmentsCentavos: (m['adjustmentsCentavos'] ?? 0) as int,
      );

  Map<String, dynamic> toCreateMap() => {
        'companyId': companyId,
        'name': name,
        'originalBudgetCentavos': originalBudget.centavos,
        'availableBalanceCentavos': availableBalance.centavos,
        'lowBalanceThresholdPct': lowBalanceThresholdPct,
        'status': status.name,
        'adjustmentsCentavos': adjustmentsCentavos,
        'createdAt': FieldValue.serverTimestamp(),
      };

  @override
  List<Object?> get props =>
      [id, companyId, name, originalBudget, availableBalance, lowBalanceThresholdPct, status, adjustmentsCentavos];
}
