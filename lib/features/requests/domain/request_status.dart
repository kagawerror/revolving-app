enum RequestStatus {
  draft,
  pendingAck,
  acknowledged,
  rejected,
  readyForRelease,
  released,
  replenished;

  static const Map<RequestStatus, Set<RequestStatus>> _allowed = {
    RequestStatus.draft: {RequestStatus.pendingAck},
    RequestStatus.pendingAck: {RequestStatus.acknowledged, RequestStatus.rejected},
    RequestStatus.acknowledged: {RequestStatus.readyForRelease},
    RequestStatus.readyForRelease: {RequestStatus.released},
    RequestStatus.released: {RequestStatus.replenished},
    RequestStatus.rejected: {},
    RequestStatus.replenished: {},
  };

  static RequestStatus fromName(String? n) => RequestStatus.values
      .firstWhere((s) => s.name == n, orElse: () => RequestStatus.draft);

  bool canTransitionTo(RequestStatus next) => _allowed[this]!.contains(next);

  void ensureTransition(RequestStatus next) {
    if (!canTransitionTo(next)) {
      throw StateError('Illegal transition: $name → ${next.name}');
    }
  }
}
