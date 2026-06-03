import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'alerts_screen.dart';
import 'notification_providers.dart';

/// App-bar bell that badges the unread alert count and opens [AlertsScreen].
class AlertsBell extends ConsumerWidget {
  const AlertsBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadCountProvider);
    final icon = count > 0
        ? Badge(label: Text('$count'), child: const Icon(Icons.notifications))
        : const Icon(Icons.notifications);
    return IconButton(
      icon: icon,
      onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AlertsScreen())),
    );
  }
}
