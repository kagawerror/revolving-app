import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/error/failure.dart';
import '../../core/error/result.dart';

/// Thin wrapper over `share_plus` that writes bytes to a temp file and opens the
/// platform share sheet. Returns [Result] so callers stay in the app's
/// error-handling idiom; failures are logged without any sensitive content.
///
/// Generic, format-agnostic counterpart to the report-specific
/// `ReportShareService` — used for one-off PDF exports (e.g. fund-audit
/// certificates) that already have their bytes built.
class FileShareService {
  const FileShareService();

  Future<Result<void>> shareBytes(
    Uint8List bytes,
    String filename, {
    String? mimeType,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: mimeType)]),
      );
      return const Ok(null);
    } catch (e, st) {
      developer.log('file share failed',
          name: 'share', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not open the share sheet.'));
    }
  }
}

final fileShareServiceProvider =
    Provider<FileShareService>((ref) => const FileShareService());
