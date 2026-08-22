import 'ocr_text_service.dart';

/// Reconstructs visual table rows from positioned OCR fragments so a
/// column-segmented sheet reads like a row-segmented one.
///
/// ML Kit segments a bordered cash-count sheet COLUMN-wise: it emits the whole
/// face-value column as fragments, then the whole count column, so the
/// line-based [parseDenominationCounts] (which needs `<face> ... <count>` on one
/// line) sees only isolated numbers and fills nothing. This stage clusters
/// fragments by vertical position into the rows a human sees, joining each row's
/// fragments left-to-right, before the parser runs.
///
/// Pure domain: no plugin imports, no `dart:ui`. Output is one [RecognizedLine]
/// per visual row (text = the row's fragments joined with a single space, box
/// null) — consumable UNCHANGED by [parseDenominationCounts].
List<RecognizedLine> reconstructRows(List<RecognizedLine> fragments) {
  // 1. ZERO-GEOMETRY FALLBACK — never regress the row-wise case. If there's no
  // usable geometry (empty, all boxes null, or all boxes degenerate/height 0)
  // return the input unchanged so already-row-segmented OCR keeps working.
  final boxed = fragments.where((f) => f.box != null).toList();
  final usable = boxed.where((f) => f.box!.height > 0).toList();
  if (usable.isEmpty) return fragments;

  // 2. Tolerance from the MEDIAN boxed height (robust to a stray tall/short
  // fragment), floored at 1.0 so we never cluster on a zero tolerance.
  final tol = _max(_median(usable.map((f) => f.box!.height)) * 0.6, 1.0);

  // 3. Sort boxed fragments by vertical center, then greedy single-link sweep:
  // add the next fragment to the open cluster while its centerY is within [tol]
  // of the cluster's running MEAN centerY (re-averaged as members join so gentle
  // skew is tracked); otherwise close the cluster and open a new one.
  final sorted = [...usable]
    ..sort((a, b) => a.box!.centerY.compareTo(b.box!.centerY));

  final clusters = <List<RecognizedLine>>[];
  var current = <RecognizedLine>[];
  var anchorY = 0.0; // running mean centerY of the current cluster

  for (final frag in sorted) {
    final cy = frag.box!.centerY;
    if (current.isEmpty) {
      current = [frag];
      anchorY = cy;
      continue;
    }
    if ((cy - anchorY) <= tol) {
      current.add(frag);
      anchorY = current.map((f) => f.box!.centerY).reduce(_add) / current.length;
    } else {
      clusters.add(current);
      current = [frag];
      anchorY = cy;
    }
  }
  if (current.isNotEmpty) clusters.add(current);

  // 4. Within each cluster, order fragments left-to-right and join with a space.
  // 5. Clusters are already emitted top-to-bottom (sorted-by-y sweep), which is
  // deterministic.
  final rows = <RecognizedLine>[
    for (final cluster in clusters)
      RecognizedLine(
        (cluster..sort((a, b) => a.box!.left.compareTo(b.box!.left)))
            .map((f) => f.text)
            .join(' '),
      ),
  ];

  // Mixed null/degenerate fragments are never dropped: append each as its own
  // single-line row at the end so its text still reaches the parser.
  for (final frag in fragments) {
    final isUsable = frag.box != null && frag.box!.height > 0;
    if (!isUsable) rows.add(RecognizedLine(frag.text));
  }

  return rows;
}

double _add(double a, double b) => a + b;
double _max(double a, double b) => a > b ? a : b;

/// Median of a finite iterable. Returns 0 for empty input (callers guard so this
/// is never hit with empty data).
double _median(Iterable<double> values) {
  final list = [...values]..sort();
  if (list.isEmpty) return 0;
  final mid = list.length ~/ 2;
  if (list.length.isOdd) return list[mid];
  return (list[mid - 1] + list[mid]) / 2;
}
