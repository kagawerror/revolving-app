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

  const Fund({
    required this.id,
    required this.companyId,
    required this.name,
    required this.originalBudget,
    required this.availableBalance,
    required this.lowBalanceThresholdPct,
    required this.status,
  });

  Money get lowBalanceThreshold =>
      originalBudget.percentageOf(lowBalanceThresholdPct);

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
      );

  Map<String, dynamic> toCreateMap() => {
        'companyId': companyId,
        'name': name,
        'originalBudgetCentavos': originalBudget.centavos,
        'availableBalanceCentavos': availableBalance.centavos,
        'lowBalanceThresholdPct': lowBalanceThresholdPct,
        'status': status.name,
        'createdAt': FieldValue.serverTimestamp(),
      };

  @override
  List<Object?> get props =>
      [id, companyId, name, originalBudget, availableBalance, lowBalanceThresholdPct, status];
}
