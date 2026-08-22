import '../../../core/money/money.dart';

/// True when releasing [intentAmount] would exceed [serverBalance] — i.e. the
/// fund cannot cover it. An EXACTLY-equal balance is NOT an overdraft (you may
/// spend the fund down to zero).
bool isOverdraft(Money serverBalance, Money intentAmount) =>
    intentAmount > serverBalance;
