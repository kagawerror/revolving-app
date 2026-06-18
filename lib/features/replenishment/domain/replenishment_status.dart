enum ReplenishmentStatus {
  draft,
  submitted,
  approved,
  rejected;

  // Auto-approve lifecycle: the incharge's submit credits the fund and lands the
  // report directly in `approved` (no approver gate). The legacy
  // submitted->{approved,rejected} edge is kept so any in-flight `submitted`
  // docs (created before this change) can still be drained by the legacy
  // approve()/reject() paths. draft->rejected covers discardDraft.
  static const Map<ReplenishmentStatus, Set<ReplenishmentStatus>> _allowed = {
    ReplenishmentStatus.draft: {ReplenishmentStatus.approved, ReplenishmentStatus.rejected},
    ReplenishmentStatus.submitted: {ReplenishmentStatus.approved, ReplenishmentStatus.rejected},
    ReplenishmentStatus.approved: {},
    ReplenishmentStatus.rejected: {},
  };

  static ReplenishmentStatus fromName(String? n) => ReplenishmentStatus.values
      .firstWhere((s) => s.name == n, orElse: () => ReplenishmentStatus.draft);

  bool canTransitionTo(ReplenishmentStatus next) => _allowed[this]!.contains(next);
}
