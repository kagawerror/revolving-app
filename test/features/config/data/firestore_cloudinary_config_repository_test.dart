import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/config/data/firestore_cloudinary_config_repository.dart';
import 'package:rev_app/features/config/domain/cloudinary_config.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  test('watch emits null when the doc is missing, then config after upsert',
      () async {
    final repo = FirestoreCloudinaryConfigRepository(db);

    expect(await repo.watch().first, isNull);

    await repo.upsert(
      const CloudinaryConfig(cloudName: 'cloud', uploadPreset: 'up'),
      'actor-1',
    );

    final emitted = await repo
        .watch()
        .firstWhere((c) => c != null && c.cloudName == 'cloud');
    expect(emitted!.cloudName, 'cloud');
    expect(emitted.uploadPreset, 'up');
    expect(emitted.updatedByUid, 'actor-1');
  });

  test('get returns Ok(null) when absent and Ok(config) once present',
      () async {
    final repo = FirestoreCloudinaryConfigRepository(db);

    final absent = await repo.get();
    expect(absent.isOk, isTrue);
    expect(absent.valueOrNull, isNull);

    await repo.upsert(
      const CloudinaryConfig(cloudName: 'cloud', uploadPreset: 'up'),
      'actor-2',
    );

    final present = await repo.get();
    expect(present.isOk, isTrue);
    expect(present.valueOrNull?.cloudName, 'cloud');
  });

  test('upsert merges — untouched fields are preserved across writes',
      () async {
    final repo = FirestoreCloudinaryConfigRepository(db);

    final first = await repo.upsert(
      const CloudinaryConfig(
        cloudName: 'cloud',
        uploadPreset: 'up',
        apiKey: 'key-1',
        uploadFolder: 'folder-1',
      ),
      'actor-1',
    );
    expect(first.isOk, isTrue);

    // Second write keeps cloudName but blanks apiKey/folder via the model.
    await repo.upsert(
      const CloudinaryConfig(cloudName: 'cloud-2', uploadPreset: 'up-2'),
      'actor-2',
    );

    // Read raw doc: merged write means earlier keys for fields the model still
    // writes (every field) are overwritten, and unmanaged keys would survive.
    final snap = await db.collection('appConfig').doc('cloudinary').get();
    final data = snap.data()!;
    expect(data['cloudName'], 'cloud-2');
    expect(data['updatedByUid'], 'actor-2');
    // Stash an out-of-band field directly, then upsert, and confirm merge kept it.
    await db
        .collection('appConfig')
        .doc('cloudinary')
        .set({'externalNote': 'keep-me'}, SetOptions(merge: true));
    await repo.upsert(
      const CloudinaryConfig(cloudName: 'cloud-3', uploadPreset: 'up-3'),
      'actor-3',
    );
    final after = await db.collection('appConfig').doc('cloudinary').get();
    expect(after.data()!['externalNote'], 'keep-me');
    expect(after.data()!['cloudName'], 'cloud-3');
  });
}
