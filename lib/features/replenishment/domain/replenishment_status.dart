enum ReplenishmentStatus {
  draft,
  submitted,
  approved,
  rejected;

  static const Map<ReplenishmentStatus, Set<ReplenishmentStatus>> _allowed = {
    ReplenishmentStatus.draft: {ReplenishmentStatus.submitted},
    ReplenishmentStatus.submitted: {ReplenishmentStatus.approved, ReplenishmentStatus.rejected},
    ReplenishmentStatus.approved: {},
    ReplenishmentStatus.rejected: {},
  };

  static ReplenishmentStatus fromName(String? n) => ReplenishmentStatus.values
      .firstWhere((s) => s.name == n, orElse: () => ReplenishmentStatus.draft);

  bool canTransitionTo(ReplenishmentStatus next) => _allowed[this]!.contains(next);
}
