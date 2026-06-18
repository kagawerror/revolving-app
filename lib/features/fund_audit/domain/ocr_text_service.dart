import 'package:equatable/equatable.dart';

import '../../../core/error/result.dart';

/// Axis-aligned bounding box of a recognized fragment, in image pixels. Kept
/// plugin-free (no `dart:ui` / ML Kit `Rect`) so the pure row reconstructor and
/// parser stay unit-testable.
class TextBox extends Equatable {
  final double left, top, right, bottom;
  const TextBox(this.left, this.top, this.right, this.bottom);

  /// Vertical midpoint — the clustering key for grouping fragments into rows.
  double get centerY => (top + bottom) / 2;

  /// Absolute height; used to derive the row-clustering tolerance.
  double get height => (bottom - top).abs();

  @override
  List<Object?> get props => [left, top, right, bottom];
}

/// One fragment of text recognized from an image, optionally with its on-image
/// [box]. Kept as a plain value so the pure [parseDenominationCounts] parser and
/// row reconstructor are testable without any OCR plugin. The [box] is null when
/// geometry is unavailable (e.g. legacy callers or stubbed tests).
class RecognizedLine extends Equatable {
  final String text;
  final TextBox? box;
  const RecognizedLine(this.text, {this.box});

  @override
  List<Object?> get props => [text, box];
}

/// On-device OCR seam. The only concrete implementation wraps
/// `google_mlkit_text_recognition`; tests stub this interface.
abstract class OcrTextService {
  /// Recognizes the text in the image at [imagePath], returning one entry per
  /// detected line. Returns an [Err] on failure — never throws.
  Future<Result<List<RecognizedLine>>> recognizeLines(String imagePath);
}
