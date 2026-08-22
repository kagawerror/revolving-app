import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rev_app/features/messaging/data/http_push_sender.dart';

class _MockClient extends http.BaseClient {
  final List<http.Request> sent = [];
  final int status;
  _MockClient([this.status = 200]);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(request as http.Request);
    return http.StreamedResponse(Stream.value(utf8.encode('ok')), status);
  }
}

void main() {
  test('POSTs audience + text to the relay URL with token header', () async {
    final client = _MockClient();
    final sender = HttpPushSender(
        relayUrl: 'https://relay.example/', relayToken: 'secret', client: client);
    await sender.notify(
        companyId: 'c1', recipientRoles: ['incharge'], title: 'T', body: 'B');
    expect(client.sent, hasLength(1));
    final req = client.sent.single;
    expect(req.method, 'POST');
    expect(req.url.toString(), 'https://relay.example/');
    expect(req.headers['x-relay-token'], 'secret');
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['companyId'], 'c1');
    expect(body['recipientRoles'], ['incharge']);
    expect(body['title'], 'T');
  });

  test('swallows errors (never throws) on non-200', () async {
    final sender = HttpPushSender(
        relayUrl: 'https://relay.example/', relayToken: '', client: _MockClient(500));
    // Should complete without throwing.
    await sender.notify(
        companyId: 'c1', recipientRoles: ['incharge'], title: 'T', body: 'B');
  });

  test('no-ops when relayUrl is empty', () async {
    final client = _MockClient();
    final sender = HttpPushSender(relayUrl: '', relayToken: '', client: client);
    await sender.notify(
        companyId: 'c1', recipientRoles: ['incharge'], title: 'T', body: 'B');
    expect(client.sent, isEmpty);
  });
}
