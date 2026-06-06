import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/app_version_info.dart';

/// Fetches the hosted update manifest. Implementations never throw — they return
/// a [Result] so a failed update check can be handled silently.
abstract class UpdateRepository {
  Future<Result<AppVersionInfo>> fetchLatest();
}

class HttpUpdateRepository implements UpdateRepository {
  HttpUpdateRepository({
    required http.Client client,
    required String manifestUrl,
  })  :
        // Public param names intentionally differ from the private fields, so
        // initializing formals aren't applicable here.
        // ignore: prefer_initializing_formals
        _client = client,
        // ignore: prefer_initializing_formals
        _manifestUrl = manifestUrl;

  final http.Client _client;
  final String _manifestUrl;

  @override
  Future<Result<AppVersionInfo>> fetchLatest() async {
    try {
      final resp = await _client.get(Uri.parse(_manifestUrl));
      if (resp.statusCode != 200) {
        return Err(UnexpectedFailure(
            'Update check failed (HTTP ${resp.statusCode}).'));
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        return const Err(ValidationFailure('Update manifest is not an object.'));
      }
      final info = AppVersionInfo.fromMap(decoded);
      if (info == null) {
        return const Err(ValidationFailure('Update manifest is malformed.'));
      }
      return Ok(info);
    } catch (e, st) {
      developer.log('fetchLatest failed', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not check for updates.'));
    }
  }
}
