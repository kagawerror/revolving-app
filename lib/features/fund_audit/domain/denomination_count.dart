import 'package:equatable/equatable.dart';

import 'denomination.dart';

/// A single row of a physical cash count: how many pieces of one [Denomination]
/// were counted. The subtotal is computed in integer centavos — never `double`.
class DenominationCount extends Equatable {
  final Denomination denomination;
  final int count;

  const DenominationCount({required this.denomination, required this.count});

  /// `denomination.centavos * count`.
  int get subtotalCentavos => denomination.centavos * count;

  @override
  List<Object?> get props => [denomination, count];
}
