import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/cloudinary_config.dart';
import '../domain/cloudinary_config_repository.dart';

class FirestoreCloudinaryConfigRepository
    implements CloudinaryConfigRepository {
  final FirebaseFirestore _db;
  FirestoreCloudinaryConfigRepository(this._db);

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection('appConfig').doc('cloudinary');

  @override
  Stream<CloudinaryConfig?> watch() => _doc.snapshots().map(
        (s) =>
            s.exists ? CloudinaryConfig.fromMap(s.data() ?? const {}) : null,
      );

  @override
  Future<Result<CloudinaryConfig?>> get() async {
    try {
      final snap = await _doc.get();
      if (!snap.exists) return const Ok(null);
      return Ok(CloudinaryConfig.fromMap(snap.data() ?? const {}));
    } catch (e, st) {
      // Never log field values — generic message only.
      developer.log('cloudinary config read failed',
          name: 'config', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not load the configuration.'));
    }
  }

  @override
  Future<Result<void>> upsert(CloudinaryConfig config, String actorUid) async {
    try {
      await _doc.set(config.toUpdateMap(actorUid), SetOptions(merge: true));
      return const Ok(null);
    } catch (e, st) {
      developer.log('cloudinary config write failed',
          name: 'config', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not save the configuration.'));
    }
  }
}
