import 'package:equatable/equatable.dart';

/// The kind of queued mutation an outbox entry represents.
enum OutboxKind { createRequest, release, transition, approverDecision }

/// Lifecycle of an outbox entry as the drain progresses.
enum OutboxState { pending, uploading, replaying, done, conflict, failed }

/// A single durable, replayable mutation captured while offline (or online but
/// queued for ordering/idempotency). Persisted via shared_preferences in a
/// later phase — hence [toJson]/[fromJson]. Pure data; no Firebase.
class OutboxEntry extends Equatable {
  final String id;
  final OutboxKind kind;
  final String companyId;

  /// The id of the entity (request) this mutation targets — used for FK
  /// ordering (a createRequest must precede any release/transition on it).
  final String entityId;

  /// Stable client-minted id for idempotent replay + dedupe across devices.
  final String clientActionId;
  final int createdAtMillis;
  final int attempts;
  final OutboxState state;
  final Map<String, dynamic> payload;

  /// Local image files to upload before replaying this mutation.
  final List<String> localImagePaths;

  const OutboxEntry({
    required this.id,
    required this.kind,
    required this.companyId,
    required this.entityId,
    required this.clientActionId,
    required this.createdAtMillis,
    this.attempts = 0,
    this.state = OutboxState.pending,
    this.payload = const {},
    this.localImagePaths = const [],
  });

  OutboxEntry copyWith({
    String? id,
    OutboxKind? kind,
    String? companyId,
    String? entityId,
    String? clientActionId,
    int? createdAtMillis,
    int? attempts,
    OutboxState? state,
    Map<String, dynamic>? payload,
    List<String>? localImagePaths,
  }) =>
      OutboxEntry(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        companyId: companyId ?? this.companyId,
        entityId: entityId ?? this.entityId,
        clientActionId: clientActionId ?? this.clientActionId,
        createdAtMillis: createdAtMillis ?? this.createdAtMillis,
        attempts: attempts ?? this.attempts,
        state: state ?? this.state,
        payload: payload ?? this.payload,
        localImagePaths: localImagePaths ?? this.localImagePaths,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'companyId': companyId,
        'entityId': entityId,
        'clientActionId': clientActionId,
        'createdAtMillis': createdAtMillis,
        'attempts': attempts,
        'state': state.name,
        'payload': payload,
        'localImagePaths': localImagePaths,
      };

  factory OutboxEntry.fromJson(Map<String, dynamic> j) => OutboxEntry(
        id: j['id'] as String,
        kind: OutboxKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => OutboxKind.transition,
        ),
        companyId: (j['companyId'] ?? '') as String,
        entityId: (j['entityId'] ?? '') as String,
        clientActionId: (j['clientActionId'] ?? '') as String,
        createdAtMillis: (j['createdAtMillis'] ?? 0) as int,
        attempts: (j['attempts'] ?? 0) as int,
        state: OutboxState.values.firstWhere(
          (s) => s.name == j['state'],
          orElse: () => OutboxState.pending,
        ),
        payload: Map<String, dynamic>.from(
            (j['payload'] as Map?) ?? const <String, dynamic>{}),
        localImagePaths: List<String>.from(
            (j['localImagePaths'] as List?) ?? const <String>[]),
      );

  @override
  List<Object?> get props => [
        id,
        kind,
        companyId,
        entityId,
        clientActionId,
        createdAtMillis,
        attempts,
        state,
        payload,
        localImagePaths,
      ];
}
