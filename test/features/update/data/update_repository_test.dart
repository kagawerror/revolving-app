import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rev_app/features/update/data/update_repository.dart';

const _url = 'https://h/app/version.json';

HttpUpdateRepository _repo(MockClient client) =>
    HttpUpdateRepository(client: client, manifestUrl: _url);

void main() {
  group('HttpUpdateRepository.fetchLatest', () {
    test('valid JSON -> Ok(AppVersionInfo)', () async {
      final client = MockClient((req) async => http.Response(
            '{"versionCode":2,"versionName":"1.1.0","apkUrl":"https://h/a.apk"}',
            200,
          ));
      final result = await _repo(client).fetchLatest();
      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.versionCode, 2);
    });

    test('non-200 -> Err', () async {
      final client = MockClient((req) async => http.Response('nope', 404));
      final result = await _repo(client).fetchLatest();
      expect(result.isOk, isFalse);
    });

    test('malformed manifest -> Err', () async {
      final client = MockClient(
          (req) async => http.Response('{"versionCode":"x"}', 200));
      final result = await _repo(client).fetchLatest();
      expect(result.isOk, isFalse);
    });

    test('non-JSON body -> Err', () async {
      final client =
          MockClient((req) async => http.Response('<html>', 200));
      final result = await _repo(client).fetchLatest();
      expect(result.isOk, isFalse);
    });

    test('network throw -> Err (no exception escapes)', () async {
      final client = MockClient((req) async => throw Exception('offline'));
      final result = await _repo(client).fetchLatest();
      expect(result.isOk, isFalse);
    });
  });
}
