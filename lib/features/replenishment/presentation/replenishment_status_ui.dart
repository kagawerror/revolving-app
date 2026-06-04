import 'package:flutter/material.dart';

import '../../../core/widgets/status_pill.dart';
import '../domain/replenishment_status.dart';

/// Presentation-only mapping from a [ReplenishmentStatus] to its shared
/// [StatusTone], human label, and icon. Owned by the replenishment presentation
/// layer so the same status looks identical on every replenishment surface.
StatusTone replenishmentStatusTone(ReplenishmentStatus status) {
  switch (status) {
    case ReplenishmentStatus.draft:
      return StatusTone.neutral;
    case ReplenishmentStatus.submitted:
      return StatusTone.warning; // awaiting an approver's action
    case ReplenishmentStatus.approved:
      return StatusTone.success;
    case ReplenishmentStatus.rejected:
      return StatusTone.danger;
  }
}

String replenishmentStatusLabel(ReplenishmentStatus status) {
  switch (status) {
    case ReplenishmentStatus.draft:
      return 'Draft';
    case ReplenishmentStatus.submitted:
      return 'Awaiting approval';
    case ReplenishmentStatus.approved:
      return 'Approved';
    case ReplenishmentStatus.rejected:
      return 'Rejected';
  }
}

IconData replenishmentStatusIcon(ReplenishmentStatus status) {
  switch (status) {
    case ReplenishmentStatus.draft:
      return Icons.edit_note_rounded;
    case ReplenishmentStatus.submitted:
      return Icons.hourglass_top_rounded;
    case ReplenishmentStatus.approved:
      return Icons.check_circle_rounded;
    case ReplenishmentStatus.rejected:
      return Icons.cancel_rounded;
  }
}
