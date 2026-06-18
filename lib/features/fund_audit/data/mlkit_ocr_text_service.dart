import 'dart:developer' as developer;
import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/ocr_text_service.dart';

/// On-device OCR via Google ML Kit. This is the ONLY file that imports the
/// `google_mlkit_text_recognition` plugin, keeping the rest of the feature
/// plugin-free and unit-testable against [OcrTextService].
class MlkitOcrTextService implements OcrTextService {
  final TextRecognizer _recognizer;
  MlkitOcrTextService({TextRecognizer? recognizer})
      : _recognizer =
            recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<Result<List<RecognizedLine>>> recognizeLines(String imagePath) async {
    try {
      final input = InputImage.fromFilePath(imagePath);
      final recognized = await _recognizer.processImage(input);
      // Carry each line's bounding box through the seam so the pure
      // [reconstructRows] stage can rebuild visual rows from a sheet ML Kit
      // segments column-wise.
      final lines = <RecognizedLine>[
        for (final block in recognized.blocks)
          for (final line in block.lines)
            RecognizedLine(line.text, box: _toBox(line.boundingBox)),
      ];
      return Ok(lines);
    } catch (e, st) {
      developer.log('ocr recognize failed',
          name: 'fund_audit', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not read the photo. Enter counts manually.'));
    }
  }

  /// Converts an ML Kit `Rect` into the plugin-free [TextBox] the pure
  /// reconstructor/parser consume.
  TextBox _toBox(Rect r) => TextBox(r.left, r.top, r.right, r.bottom);

  /// Releases the native recognizer. Call when the owning provider disposes.
  Future<void> dispose() => _recognizer.close();
}
