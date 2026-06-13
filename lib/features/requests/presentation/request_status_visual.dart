import 'package:flutter/material.dart';

import '../../../core/widgets/status_pill.dart';
import '../domain/request_status.dart';

/// Maps a [RequestStatus] to a consistent, color-coded pill tone + readable
/// label + icon. This is the single source of truth shared by the requests
/// screens and the dashboard so the same status always looks the same app-wide.
({String label, StatusTone tone, IconData icon}) requestStatusVisual(
    RequestStatus status) {
  switch (status) {
    case RequestStatus.created:
      return (label: 'To release', tone: StatusTone.warning, icon: Icons.hourglass_top_rounded);
    case RequestStatus.released:
      return (label: 'Released', tone: StatusTone.success, icon: Icons.payments_rounded);
    case RequestStatus.acknowledged:
      return (label: 'Acknowledged', tone: StatusTone.info, icon: Icons.verified_rounded);
    case RequestStatus.disputed:
      return (label: 'Disputed', tone: StatusTone.danger, icon: Icons.report_problem_rounded);
    case RequestStatus.conflict:
      return (label: 'Conflict', tone: StatusTone.danger, icon: Icons.error_outline_rounded);
    case RequestStatus.rejected:
      return (label: 'Rejected', tone: StatusTone.danger, icon: Icons.cancel_rounded);
    case RequestStatus.replenished:
      return (label: 'Replenished', tone: StatusTone.success, icon: Icons.autorenew_rounded);
  }
}
