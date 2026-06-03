import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_providers.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(myNotificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: alerts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('No alerts'))
            : ListView(children: [
                for (final n in list)
                  ListTile(
                    leading: Icon(n.isUnread ? Icons.circle : Icons.circle_outlined,
                        size: 12,
                        color: n.isUnread ? Theme.of(context).colorScheme.primary : null),
                    title: Text(n.title),
                    subtitle: Text(n.body),
                    onTap: n.isUnread
                        ? () => ref.read(notificationRepositoryProvider).markRead(n.id).ignore()
                        : null,
                  ),
              ]),
      ),
    );
  }
}
