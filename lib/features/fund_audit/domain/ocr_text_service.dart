import 'package:equatable/equatable.dart';

import '../../../core/error/result.dart';

/// One line of text recognized from an image. Kept as a plain value so the pure
/// [parseDenominationCounts] parser is testable without any OCR plugin.
class RecognizedLine extends Equatable {
  final String text;
  const RecognizedLine(this.text);

  @override
  List<Object?> get props => [text];
}

/// On-device OCR seam. The only concrete implementation wraps
/// `google_mlkit_text_recognition`; tests stub this interface.
abstract class OcrTextService {
  /// Recognizes the text in the image at [imagePath], returning one entry per
  /// detected line. Returns an [Err] on failure — never throws.
  Future<Result<List<RecognizedLine>>> recognizeLines(String imagePath);
}
