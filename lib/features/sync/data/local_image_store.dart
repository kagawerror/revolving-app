import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/ids.dart';

/// Persists captured proof/signature image bytes to disk until the sync engine
/// uploads them. Local-only; it never touches Cloudinary or Firestore.
///
/// The base directory is injected as a `Future<Directory> Function()` so tests
/// use a temp dir and production wires `getApplicationDocumentsDirectory`
/// behind `localImageStoreProvider`. Files live under a dedicated
/// `offline_images/` subfolder, created on first write.
///
/// PRIVACY: image bytes ARE the PII (proof photos). This class never logs
/// bytes or paths — only generic, content-free diagnostics.
class LocalImageStore {
  LocalImageStore({required this.baseDir});

  static const String _subfolder = 'offline_images';

  /// Resolves the base directory under which `offline_images/` is created.
  /// Injected so tests use a temp dir and production wires
  /// `getApplicationDocumentsDirectory` (see localImageStoreProvider).
  final Future<Directory> Function() baseDir;

  Future<Directory> _dir() async {
    final base = await baseDir();
    final dir = Directory('${base.path}/$_subfolder');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Writes [bytes] to a new file named `<clientId><suffix>` (e.g. `.jpg`) and
  /// returns its absolute path. [suffix] should include the leading dot.
  Future<Result<String>> save(List<int> bytes, {required String suffix}) async {
    try {
      final dir = await _dir();
      final file = File('${dir.path}/${newClientId()}$suffix');
      await file.writeAsBytes(bytes, flush: true);
      return Ok(file.path);
    } catch (e) {
      // Log only the error TYPE: FileSystemException.toString() embeds the
      // file path, which is PII-adjacent (this class promises to never log
      // paths). The type alone is enough to diagnose without leaking it.
      developer.log('Local image store: save failed (${e.runtimeType}).',
          name: 'LocalImageStore');
      return const Err(UnexpectedFailure('Could not save the image locally.'));
    }
  }

  /// Reads the bytes at [path]. Returns [NotFoundFailure] if the file is gone.
  Future<Result<List<int>>> read(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return const Err(NotFoundFailure('The local image is no longer available.'));
      }
      return Ok(await file.readAsBytes());
    } catch (e) {
      // Log only the error TYPE (see save): FileSystemException.toString()
      // would embed the path this class promises never to log.
      developer.log('Local image store: read failed (${e.runtimeType}).',
          name: 'LocalImageStore');
      return const Err(UnexpectedFailure('Could not read the local image.'));
    }
  }

  /// Deletes the file at [path]. Reports failure (use [deleteQuietly] for
  /// best-effort cleanup that should never surface an error).
  Future<Result<void>> delete(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
      return const Ok(null);
    } catch (e) {
      // Log only the error TYPE (see save): FileSystemException.toString()
      // would embed the path this class promises never to log.
      developer.log('Local image store: delete failed (${e.runtimeType}).',
          name: 'LocalImageStore');
      return const Err(UnexpectedFailure('Could not delete the local image.'));
    }
  }

  /// Best-effort cleanup after a successful upload. Never throws.
  Future<void> deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      developer.log('Local image store: quiet delete failed.',
          name: 'LocalImageStore');
    }
  }
}
