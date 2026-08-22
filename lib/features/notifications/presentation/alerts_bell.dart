import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import 'alerts_screen.dart';
import 'notification_providers.dart';

/// App-bar bell that opens [AlertsScreen]. For approvers (superior/manager/ceo)
/// it badges the number of replenishments awaiting their decision; for everyone
/// else it badges the unread-alert count. Admins keep the unread count.
class AlertsBell extends ConsumerWidget {
  const AlertsBell({super.key});

  /// Role-aware tooltip text. Kept pure for readability.
  static String tooltipFor({required bool isApprover, required int count}) {
    if (isApprover) {
      if (count == 0) return 'Approvals';
      if (count == 1) return 'Alerts (1 pending approval)';
      return 'Alerts ($count pending approvals)';
    }
    if (count == 0) return 'Alerts';
    if (count == 1) return 'Alerts (1 unread)';
    return 'Alerts ($count unread)';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isApprover = user?.role.canApprove ?? false;
    final count = isApprover
        ? ref.watch(pendingApprovalCountProvider)
        : ref.watch(unreadCountProvider);

    const bell = Icon(Icons.notifications_rounded);
    final icon = count > 0
        ? Badge(
            // Clamp the visible label so a runaway count never blows out the
            // badge — the underlying count logic is untouched.
            label: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
            backgroundColor: scheme.error,
            textColor: scheme.onError,
            child: bell,
          )
        : bell;

    return IconButton(
      tooltip: tooltipFor(isApprover: isApprover, count: count),
      icon: icon,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AlertsScreen()),
      ),
    );
  }
}
