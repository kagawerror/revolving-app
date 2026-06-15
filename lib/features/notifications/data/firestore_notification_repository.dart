import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/app_notification.dart';
import '../domain/notification_repository.dart';

class FirestoreNotificationRepository implements NotificationRepository {
  final FirebaseFirestore _db;
  FirestoreNotificationRepository(this._db);

  @override
  Stream<List<AppNotification>> watchForRole(String companyId, String role) => _db
      .collection('notifications')
      .where('companyId', isEqualTo: companyId)
      .where('recipientRoles', arrayContains: role)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map((d) => AppNotification.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<AppNotification>> watchAllForRole(String role) => _db
      .collection('notifications')
      .where('recipientRoles', arrayContains: role)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map((d) => AppNotification.fromMap(d.id, d.data())).toList());

  @override
  Future<void> markRead(String id) =>
      _db.collection('notifications').doc(id).update({'readAt': FieldValue.serverTimestamp()});
}
