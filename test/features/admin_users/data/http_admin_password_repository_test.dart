import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/admin_users/data/http_admin_password_repository.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

/// http.BaseClient stub recording the single request and replaying a canned
/// status — mirrors the messaging test's _MockClient style, but lets each test
/// pick the status code and optionally throw to simulate a network failure.
class _StubClient extends http.BaseClient {
  _StubClient({this.status = 200, this.throwError});
  final int status;
  final Object? throwError;
  final List<http.Request> sent = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(request as http.Request);
    if (throwError != null) throw throwError!;
    return http.StreamedResponse(
      Stream.value(utf8.encode(status == 200 ? '{"ok":true}' : 'err')),
      status,
    );
  }
}

const _relay = 'https://admin.example';

HttpAdminPasswordRepository _repo(
  http.Client client, {
  String relayUrl = _relay,
  String? token = 'id-token-123',
}) {
  final auth = _MockAuth();
  if (token == null) {
    when(() => auth.currentUser).thenReturn(null);
  } else {
    final user = _MockUser();
    when(() => user.getIdToken()).thenAnswer((_) async => token);
    when(() => auth.currentUser).thenReturn(user);
  }
  return HttpAdminPasswordRepository(
    relayUrl: relayUrl,
    auth: auth,
    client: client,
  );
}

void main() {
  test('200 -> Ok and sends correct URL, auth header, JSON body', () async {
    final client = _StubClient(status: 200);
    final repo = _repo(client);

    final res = await repo.setUserPassword(uid: 'u1', newPassword: 'sup3rsecret');

    expect(res, isA<Ok<void>>());
    expect(client.sent, hasLength(1));
    final req = client.sent.single;
    expect(req.method, 'POST');
    expect(req.url.toString(), '$_relay/admin/set-password');
    expect(req.headers['authorization'], 'Bearer id-token-123');
    expect(req.headers['content-type'], contains('application/json'));
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body, {'uid': 'u1', 'newPassword': 'sup3rsecret'});
  });

  test('400 -> ValidationFailure', () async {
    final res = await _repo(_StubClient(status: 400))
        .setUserPassword(uid: 'u1', newPassword: 'x');
    expect(res.failureOrNull, isA<ValidationFailure>());
  });

  test('401 -> AuthFailure', () async {
    final res = await _repo(_StubClient(status: 401))
        .setUserPassword(uid: 'u1', newPassword: 'x');
    expect(res.failureOrNull, isA<AuthFailure>());
  });

  test('403 -> PermissionFailure', () async {
    final res = await _repo(_StubClient(status: 403))
        .setUserPassword(uid: 'u1', newPassword: 'x');
    expect(res.failureOrNull, isA<PermissionFailure>());
  });

  test('404 -> NotFoundFailure', () async {
    final res = await _repo(_StubClient(status: 404))
        .setUserPassword(uid: 'u1', newPassword: 'x');
    expect(res.failureOrNull, isA<NotFoundFailure>());
  });

  test('500 -> UnexpectedFailure', () async {
    final res = await _repo(_StubClient(status: 500))
        .setUserPassword(uid: 'u1', newPassword: 'x');
    expect(res.failureOrNull, isA<UnexpectedFailure>());
  });

  test('empty relayUrl -> configured UnexpectedFailure, no request sent',
      () async {
    final client = _StubClient();
    final repo = _repo(client, relayUrl: '');
    final res = await repo.setUserPassword(uid: 'u1', newPassword: 'x');
    expect(res.failureOrNull, isA<UnexpectedFailure>());
    expect(res.failureOrNull!.message, 'Password reset is not configured.');
    expect(client.sent, isEmpty);
  });

  test('null token (signed out) -> AuthFailure, no request sent', () async {
    final client = _StubClient();
    final repo = _repo(client, token: null);
    final res = await repo.setUserPassword(uid: 'u1', newPassword: 'x');
    expect(res.failureOrNull, isA<AuthFailure>());
    expect(client.sent, isEmpty);
  });

  test('timeout / network error -> UnexpectedFailure (never throws)', () async {
    final repo = _repo(_StubClient(throwError: TimeoutException('boom')));
    final res = await repo.setUserPassword(uid: 'u1', newPassword: 'x');
    expect(res.failureOrNull, isA<UnexpectedFailure>());
    expect(res.failureOrNull!.message, 'Network error. Try again.');
  });
}
