import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/sync/data/local_image_store.dart';

void main() {
  late Directory tmp;
  late LocalImageStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lis_test');
    store = LocalImageStore(baseDir: () async => tmp);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('save then read round-trips the bytes', () async {
    final bytes = [1, 2, 3, 4, 5];
    final saved = await store.save(bytes, suffix: '.jpg');
    expect(saved, isA<Ok<String>>());
    final path = (saved as Ok<String>).value;
    expect(path.endsWith('.jpg'), isTrue);

    final read = await store.read(path);
    expect(read, isA<Ok<List<int>>>());
    expect((read as Ok<List<int>>).value, bytes);
  });

  test('save creates the offline_images subfolder', () async {
    final sub = Directory('${tmp.path}/offline_images');
    expect(sub.existsSync(), isFalse);
    await store.save([9], suffix: '.jpg');
    expect(sub.existsSync(), isTrue);
  });

  test('save writes under the offline_images subfolder', () async {
    final saved = await store.save([7], suffix: '.png');
    final path = (saved as Ok<String>).value;
    expect(path.contains('offline_images'), isTrue);
  });

  test('reading a missing file returns NotFoundFailure', () async {
    final read = await store.read('${tmp.path}/offline_images/nope.jpg');
    expect(read, isA<Err<List<int>>>());
    expect((read as Err<List<int>>).failure, isA<NotFoundFailure>());
  });

  test('delete removes the file', () async {
    final saved = await store.save([1], suffix: '.jpg');
    final path = (saved as Ok<String>).value;
    expect(File(path).existsSync(), isTrue);

    final del = await store.delete(path);
    expect(del, isA<Ok<void>>());
    expect(File(path).existsSync(), isFalse);
  });

  test('deleteQuietly swallows errors for a missing file', () async {
    // Should not throw.
    await store.deleteQuietly('${tmp.path}/offline_images/ghost.jpg');
  });

  test('two saves produce distinct filenames', () async {
    final a = (await store.save([1], suffix: '.jpg') as Ok<String>).value;
    final b = (await store.save([2], suffix: '.jpg') as Ok<String>).value;
    expect(a, isNot(b));
  });
}
