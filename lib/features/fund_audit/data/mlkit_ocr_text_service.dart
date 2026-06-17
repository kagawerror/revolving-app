import 'dart:developer' as developer;

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
      final lines = <RecognizedLine>[
        for (final block in recognized.blocks)
          for (final line in block.lines) RecognizedLine(line.text),
      ];
      return Ok(lines);
    } catch (e, st) {
      developer.log('ocr recognize failed',
          name: 'fund_audit', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not read the photo. Enter counts manually.'));
    }
  }

  /// Releases the native recognizer. Call when the owning provider disposes.
  Future<void> dispose() => _recognizer.close();
}
