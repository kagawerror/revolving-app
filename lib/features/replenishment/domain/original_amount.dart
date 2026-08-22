import '../../requests/domain/fund_request.dart';

/// Sum, in centavos, of the OUTSTANDING original amounts of the selected
/// requests — i.e. the full total still owed back to the fund before any
/// partial is applied. Pure (no Firebase); the seam for the "original amount
/// when partial" display on a replenishment.
///
/// We sum [FundRequest.remaining] (amount − already-replenished) rather than the
/// raw [FundRequest.amount]: when a request has already had a prior partial
/// returned, the original total still owed for THIS replenishment is what is
/// left outstanding. A fresh (un-partialled) request's `remaining` equals its
/// `amount`, so the common case is unaffected.
int sumOriginalCentavos(Iterable<FundRequest> selected) {
  var total = 0;
  for (final r in selected) {
    total += r.remaining.centavos;
  }
  return total;
}
