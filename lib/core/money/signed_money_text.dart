import 'package:intl/intl.dart';

/// Formats SIGNED centavos as a peso string — for the rare display values that
/// can legitimately go negative and so cannot be held by [Money] (which is
/// non-negative by construction). The canonical example is an
/// `OptimisticBalance`, where two un-synced offline releases can over-commit a
/// fund below zero and the UI must show that honestly rather than clamp it.
///
/// Mirrors `Money.format()` exactly for non-negative values (same `en_PH` `₱`
/// currency formatter) so positive balances read identically whether they came
/// through [Money] or here. A negative value renders with a leading minus, e.g.
/// `-₱1,250.00`, never as `(₱1,250.00)` accounting parens — minus is the
/// clearer, less-ambiguous signal for a custodian under pressure.
String formatSignedCentavos(int centavos) {
  final pesos = centavos / 100;
  return NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(pesos);
}
