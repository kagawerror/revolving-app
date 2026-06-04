import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'alerts_screen.dart';
import 'notification_providers.dart';

/// App-bar bell that badges the unread alert count and opens [AlertsScreen].
class AlertsBell extends ConsumerWidget {
  const AlertsBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final count = ref.watch(unreadCountProvider);

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
      tooltip: count > 0 ? 'Alerts ($count unread)' : 'Alerts',
      icon: icon,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AlertsScreen()),
      ),
    );
  }
}
