/// Release-first request lifecycle.
///
/// The incharge releases cash FIRST (creating an auditable handover with proof
/// + signature); approval is now POST-HOC — an approver acknowledges or
/// disputes the already-released spend. Overdrafts detected at sync time land
/// in `conflict` for the incharge to resolve.
///
/// This `_allowed` map is enforced TWICE: here and, independently, in the
/// `match /requests/{requestId}` block of `firestore.rules`. Change both
/// together or writes pass locally and are rejected by the server (or vice
/// versa).
enum RequestStatus {
  created,
  released,
  acknowledged,
  disputed,
  conflict,
  rejected,
  replenished;

  static const Map<RequestStatus, Set<RequestStatus>> _allowed = {
    RequestStatus.created: {RequestStatus.released, RequestStatus.rejected},
    RequestStatus.released: {
      RequestStatus.acknowledged,
      RequestStatus.disputed,
      RequestStatus.replenished,
      RequestStatus.conflict,
    },
    RequestStatus.acknowledged: {
      RequestStatus.disputed,
      RequestStatus.replenished,
    },
    RequestStatus.conflict: {RequestStatus.released, RequestStatus.rejected},
    RequestStatus.disputed: {RequestStatus.replenished},
    RequestStatus.rejected: {},
    RequestStatus.replenished: {},
  };

  /// Deserialize a persisted status name into the release-first lifecycle.
  ///
  /// In the OLD (pre-release-first) model the fund was debited ONLY on
  /// `→released`, so any legacy PRE-release status — `draft`, `pendingAck`,
  /// `readyForRelease` — names cash that was NEVER deducted. We therefore remap
  /// every legacy pre-release status (and any unknown/missing value) to
  /// `created` so the doc RE-ENTERS the release flow and the fund is debited
  /// properly. Mapping `readyForRelease` to `released` would strand
  /// un-deducted cash as if it had been handed out — never do that.
  ///
  /// `acknowledged` keeps its NEW post-release meaning (the user confirmed
  /// there is no live legacy `acknowledged` data). All current status names
  /// round-trip to themselves.
  static RequestStatus fromName(String? n) {
    switch (n) {
      case 'draft':
      case 'pendingAck':
      case 'readyForRelease':
        return RequestStatus.created;
    }
    return RequestStatus.values.firstWhere(
      (s) => s.name == n,
      orElse: () => RequestStatus.created,
    );
  }

  bool canTransitionTo(RequestStatus next) => _allowed[this]!.contains(next);

  void ensureTransition(RequestStatus next) {
    if (!canTransitionTo(next)) {
      throw StateError('Illegal transition: $name → ${next.name}');
    }
  }
}
