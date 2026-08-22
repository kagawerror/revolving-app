import 'denomination.dart';
import 'ocr_text_service.dart';

/// Pure, tolerant parser that turns OCR'd cash-sheet lines into a
/// `denomination → count` map. It is deliberately forgiving: rows it can't
/// confidently read are simply omitted, garbage yields `{}`, and it NEVER throws.
///
/// Real count sheets write EVERY denomination as a peso amount with two
/// decimals and thousands commas — `1.00`, `5.00`, `50.00`, `1,000.00` — in the
/// shape `<denomination> x <count> = <subtotal>`. So the denomination is found
/// by its FACE VALUE (in centavos) rather than by "is it a decimal", and a
/// decimal token like `1.00` is the ₱1 bill (100c), not a 1-centavo coin.
///
/// Heuristic per line:
///  1. Strip thousands commas so `1,000.00` reads as `1000.00`.
///  2. Tokenize into numeric tokens (each may carry a decimal point), in order.
///  3. Denomination = the FIRST token whose centavo value `(value * 100).round()`
///     maps to a known face value. The float only exists transiently here to
///     match a face value; it is immediately rounded to an integer centavo and
///     never stored.
///  4. Count = the first PURE-INTEGER token AFTER the denomination token (regex
///     `^\d+$`). This skips the trailing subtotal (which always carries `.00`)
///     and the `x` / `=` separators. A row with no such count token carries no
///     information and is omitted.
Map<Denomination, int> parseDenominationCounts(List<RecognizedLine> lines) {
  final result = <Denomination, int>{};

  for (final line in lines) {
    final parsed = _parseLine(line.text);
    if (parsed == null) continue;
    final (denom, count) = parsed;
    if (count <= 0) continue;
    // First confident read for a denomination wins; ignore duplicate rows.
    result.putIfAbsent(denom, () => count);
  }

  return result;
}

/// All 13 face values, in centavos, mapped to their [Denomination]. Built once
/// from the enum so it can never drift from [DenominationX.centavos].
final Map<int, Denomination> _facesByCentavos = {
  for (final d in Denomination.values) d.centavos: d,
};

/// Returns `(denomination, count)` for a single line, or `null` if it can't be
/// confidently read.
(Denomination, int)? _parseLine(String raw) {
  // Commas are thousands separators; drop them so "1,000.00" reads as 1000.00.
  final cleaned = raw.replaceAll(',', '');

  // Tokenize into numeric tokens (each may be decimal), in order.
  final tokens = RegExp(r'\d+(?:\.\d+)?')
      .allMatches(cleaned)
      .map((m) => m.group(0)!)
      .toList();
  if (tokens.length < 2) return null;

  // Find the denomination token: the first token whose face value is known.
  var denomIndex = -1;
  Denomination? denom;
  for (var i = 0; i < tokens.length; i++) {
    final match = _matchDenomination(tokens[i]);
    if (match != null) {
      denom = match;
      denomIndex = i;
      break;
    }
  }
  if (denom == null) return null;

  // Count is the first PURE-INTEGER token after the denomination token. This
  // deliberately skips the decimal subtotal (e.g. "8.00") and the separators.
  for (var i = denomIndex + 1; i < tokens.length; i++) {
    if (RegExp(r'^\d+$').hasMatch(tokens[i])) {
      final count = int.tryParse(tokens[i]);
      if (count != null) return (denom, count);
    }
  }
  return null;
}

/// Maps a numeric token (integer OR decimal peso amount) to a [Denomination] by
/// its centavo face value, or `null` if it is not a known face value.
///
/// The token is parsed to a double ONLY to convert pesos→centavos; the result
/// is immediately `.round()`ed to an integer so float drift can never leak into
/// stored amounts. `0.01`→1, `0.25`→25, `1.00`→100, `10.00`→1000,
/// `1000.00`→100000.
Denomination? _matchDenomination(String token) {
  final pesos = double.tryParse(token);
  if (pesos == null) return null;
  final centavos = (pesos * 100).round();
  return _facesByCentavos[centavos];
}
