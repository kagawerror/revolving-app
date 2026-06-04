import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/services/cloudinary/cloudinary_uploader.dart';

void main() {
  test('returns secure_url on 200', () async {
    final client = MockClient((req) async {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'secure_url': 'https://cdn/x.jpg'}))),
        200,
      );
    });
    final uploader = CloudinaryUploader(
      cloudName: 'demo', uploadPreset: 'preset', folder: 'f', client: client);
    final res = await uploader.uploadJpeg(Uint8List.fromList([1, 2, 3]));
    expect(res.valueOrNull, 'https://cdn/x.jpg');
  });

  test('returns Err on non-200', () async {
    final client = MockClient((req) async =>
        http.StreamedResponse(Stream.value(utf8.encode('bad')), 401));
    final uploader = CloudinaryUploader(
      cloudName: 'demo', uploadPreset: 'preset', folder: 'f', client: client);
    final res = await uploader.uploadJpeg(Uint8List.fromList([1]));
    expect(res.failureOrNull, isA<Failure>());
  });
}

/// Minimal MultipartRequest-aware mock.
class MockClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  MockClient(this.handler);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => handler(request);
}
