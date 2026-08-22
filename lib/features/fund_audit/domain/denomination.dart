/// Philippine peso denominations used in a physical cash count, from the 1-centavo
/// coin up to the ₱1,000 bill. Each carries its exact value in integer centavos so
/// all cash-count math stays in centavos (never `double`).
enum Denomination { c01, c05, c10, c25, p1, p5, p10, p20, p50, p100, p200, p500, p1000 }

extension DenominationX on Denomination {
  /// Exact face value in integer centavos.
  int get centavos => switch (this) {
        Denomination.c01 => 1,
        Denomination.c05 => 5,
        Denomination.c10 => 10,
        Denomination.c25 => 25,
        Denomination.p1 => 100,
        Denomination.p5 => 500,
        Denomination.p10 => 1000,
        Denomination.p20 => 2000,
        Denomination.p50 => 5000,
        Denomination.p100 => 10000,
        Denomination.p200 => 20000,
        Denomination.p500 => 50000,
        Denomination.p1000 => 100000,
      };

  /// Human label with the peso glyph, e.g. "₱0.01" … "₱1,000".
  String get label => switch (this) {
        Denomination.c01 => '₱0.01',
        Denomination.c05 => '₱0.05',
        Denomination.c10 => '₱0.10',
        Denomination.c25 => '₱0.25',
        Denomination.p1 => '₱1',
        Denomination.p5 => '₱5',
        Denomination.p10 => '₱10',
        Denomination.p20 => '₱20',
        Denomination.p50 => '₱50',
        Denomination.p100 => '₱100',
        Denomination.p200 => '₱200',
        Denomination.p500 => '₱500',
        Denomination.p1000 => '₱1,000',
      };

  /// Resolve from a stored `enum.name`, defaulting to [Denomination.c01] for an
  /// unknown token so a malformed doc never throws while reading.
  static Denomination fromName(String? name) => Denomination.values
      .firstWhere((d) => d.name == name, orElse: () => Denomination.c01);
}

/// Canonical display/count order: largest bill first down to the 1-centavo coin.
/// Cash sheets are filled top-down from ₱1,000, so this is the grid order too.
const List<Denomination> kDenominationsDescending = [
  Denomination.p1000,
  Denomination.p500,
  Denomination.p200,
  Denomination.p100,
  Denomination.p50,
  Denomination.p20,
  Denomination.p10,
  Denomination.p5,
  Denomination.p1,
  Denomination.c25,
  Denomination.c10,
  Denomination.c05,
  Denomination.c01,
];
