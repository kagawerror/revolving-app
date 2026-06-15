import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';
import '../../replenishment/domain/replenishment_fill.dart';

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

  // --- Denormalized display fields (all optional; legacy + lowBalance docs
  // parse as null). Written at notification-write time so both the incharge and
  // approver alert lists render rich rows with zero extra reads, offline-safe.
  final String? fundName;
  final String? companyName;

  /// Display name of the submitting incharge (the actor that triggered the
  /// replenishment lifecycle event).
  final String? actorName;
  final int? replenishAmountCentavos;

  /// Snapshot of the fund's available balance at write time (post-credit for
  /// approved, unchanged for submitted/rejected).
  final int? availableBalanceCentavos;

  /// 'full' | 'partial' | 'mixed' — see [ReplenishmentFill].
  final String? fillType;

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
    this.fundName,
    this.companyName,
    this.actorName,
    this.replenishAmountCentavos,
    this.availableBalanceCentavos,
    this.fillType,
  });

  bool get isUnread => readAt == null;

  /// Replenishment total as [Money], or null when not a denormalized replen alert.
  Money? get replenishAmount => replenishAmountCentavos == null
      ? null
      : Money.fromCentavos(replenishAmountCentavos!);

  /// Snapshotted fund balance as [Money], or null when absent.
  Money? get availableBalance => availableBalanceCentavos == null
      ? null
      : Money.fromCentavos(availableBalanceCentavos!);

  /// Parsed fill classification, or null for legacy/garbage/absent values.
  ReplenishmentFill? get fill => ReplenishmentFill.fromName(fillType);

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
        fundName: m['fundName'] as String?,
        companyName: m['companyName'] as String?,
        actorName: m['actorName'] as String?,
        replenishAmountCentavos: m['replenishAmountCentavos'] as int?,
        availableBalanceCentavos: m['availableBalanceCentavos'] as int?,
        fillType: m['fillType'] as String?,
      );

  @override
  List<Object?> get props => [
        id,
        companyId,
        recipientRoles,
        type,
        title,
        body,
        fundId,
        replenishmentId,
        readAt,
        fundName,
        companyName,
        actorName,
        replenishAmountCentavos,
        availableBalanceCentavos,
        fillType,
      ];
}
