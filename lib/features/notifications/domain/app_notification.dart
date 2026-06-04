import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class AppNotification extends Equatable {
  final String id;
  final String companyId;
  final List<String> recipientRoles;
  final String type;
  final String title;
  final String body;
  final String? fundId;
  final String? replenishmentId;
  final Timestamp? readAt;

  const AppNotification({
    required this.id,
    required this.companyId,
    required this.recipientRoles,
    required this.type,
    required this.title,
    required this.body,
    this.fundId,
    this.replenishmentId,
    this.readAt,
  });

  bool get isUnread => readAt == null;

  factory AppNotification.fromMap(String id, Map<String, dynamic> m) => AppNotification(
        id: id,
        companyId: (m['companyId'] ?? '') as String,
        recipientRoles: List<String>.from((m['recipientRoles'] ?? const []) as List),
        type: (m['type'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        body: (m['body'] ?? '') as String,
        fundId: m['fundId'] as String?,
        replenishmentId: m['replenishmentId'] as String?,
        readAt: m['readAt'] as Timestamp?,
      );

  @override
  List<Object?> get props =>
      [id, companyId, recipientRoles, type, title, body, fundId, replenishmentId, readAt];
}
