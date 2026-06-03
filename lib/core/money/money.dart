import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

/// Exact money value, stored as integer centavos. Never use double for money math.
class Money extends Equatable implements Comparable<Money> {
  final int centavos;

  const Money._(this.centavos);

  factory Money.fromCentavos(int centavos) {
    if (centavos < 0) {
      throw ArgumentError.value(centavos, 'centavos', 'must be >= 0');
    }
    return Money._(centavos);
  }

  factory Money.fromPesos(num pesos) => Money.fromCentavos((pesos * 100).round());

  static const Money zero = Money._(0);

  Money operator +(Money other) => Money._(centavos + other.centavos);
  Money operator -(Money other) => Money.fromCentavos(centavos - other.centavos);

  /// Integer-centavo percentage (e.g. 3% threshold of a budget).
  Money percentageOf(num percent) =>
      Money.fromCentavos((centavos * percent / 100).round());

  bool operator <(Money o) => centavos < o.centavos;
  bool operator <=(Money o) => centavos <= o.centavos;
  bool operator >(Money o) => centavos > o.centavos;
  bool operator >=(Money o) => centavos >= o.centavos;

  @override
  int compareTo(Money other) => centavos.compareTo(other.centavos);

  String format() =>
      NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(centavos / 100);

  @override
  List<Object?> get props => [centavos];
}
