import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../domain/push_sender.dart';

class HttpPushSender implements PushSender {
  final String relayUrl;
  final String relayToken;
  final http.Client client;

  HttpPushSender({
    required this.relayUrl,
    required this.relayToken,
    http.Client? client,
  }) : client = client ?? http.Client();

  @override
  Future<void> notify({
    required String companyId,
    required List<String> recipientRoles,
    required String title,
    required String body,
  }) async {
    if (relayUrl.isEmpty) return;
    try {
      await client
          .post(
            Uri.parse(relayUrl),
            headers: {
              'content-type': 'application/json',
              if (relayToken.isNotEmpty) 'x-relay-token': relayToken,
            },
            body: jsonEncode({
              'companyId': companyId,
              'recipientRoles': recipientRoles,
              'title': title,
              'body': body,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e, st) {
      // Best-effort: a failed push must never affect the triggering operation.
      developer.log('push relay failed', name: 'push', error: e, stackTrace: st);
    }
  }
}
