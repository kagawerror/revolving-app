import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/admin_password_repository.dart';
import '../domain/password_reset_rules.dart';

/// Calls the admin-relay Cloudflare Worker to set another user's password.
///
/// Mirrors `HttpPushSender`: inject an [http.Client], log only safe messages
/// via `dart:developer`, and bound the network call with a `.timeout`. The
/// admin's Firebase ID token authenticates the call (the Worker verifies the
/// caller is an admin server-side). Returns a [Result]; never throws out.
///
/// SECURITY: [newPassword], the request body, and the bearer token are NEVER
/// written to any log line.
class HttpAdminPasswordRepository implements AdminPasswordRepository {
  HttpAdminPasswordRepository({
    required this.relayUrl,
    required FirebaseAuth auth,
    http.Client? client,
  })  :
        // Public param name (`auth`) intentionally differs from the private
        // field, so an initializing formal isn't applicable here.
        // ignore: prefer_initializing_formals
        _auth = auth,
        _client = client ?? http.Client();

  final String relayUrl;
  final FirebaseAuth _auth;
  final http.Client _client;

  @override
  Future<Result<void>> setUserPassword({
    required String uid,
    required String newPassword,
  }) async {
    if (relayUrl.isEmpty) {
      return const Err(UnexpectedFailure('Password reset is not configured.'));
    }

    final token = await _auth.currentUser?.getIdToken();
    if (token == null) {
      return const Err(AuthFailure('Sign in again.'));
    }

    try {
      final resp = await _client
          .post(
            Uri.parse('$relayUrl/admin/set-password'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
            },
            body: jsonEncode({'uid': uid, 'newPassword': newPassword}),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        return const Ok(null);
      }
      return Err(mapSetPasswordStatus(resp.statusCode));
    } on TimeoutException catch (e) {
      // Safe: no body/token/password in the log.
      developer.log('admin set-password timed out', name: 'admin_pw', error: e);
      return const Err(UnexpectedFailure('Network error. Try again.'));
    } on SocketException catch (e) {
      developer.log('admin set-password network error',
          name: 'admin_pw', error: e);
      return const Err(UnexpectedFailure('Network error. Try again.'));
    } catch (e) {
      developer.log('admin set-password failed', name: 'admin_pw', error: e);
      return const Err(UnexpectedFailure('Network error. Try again.'));
    }
  }
}
