import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/replenishment.dart';
import 'replenishment_providers.dart';

class ReplenishmentDetailScreen extends ConsumerWidget {
  final Replenishment replenishment;
  const ReplenishmentDetailScreen({super.key, required this.replenishment});

  Future<void> _decide(BuildContext context, WidgetRef ref, bool approve) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final repo = ref.read(replenishmentRepositoryProvider);
    final res = approve
        ? await repo.approve(replenishment: replenishment, actorUid: user.uid)
        : await repo.reject(replenishment: replenishment, actorUid: user.uid);
    if (!context.mounted) return;
    if (res.showOnError(context)) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canApprove =
        ref.watch(currentUserProvider).valueOrNull?.role.canApprove ?? false;
    final r = replenishment;
    return Scaffold(
      appBar: AppBar(title: const Text('Replenishment')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Total: ${r.total.format()}', style: Theme.of(context).textTheme.headlineSmall),
        Text('Items: ${r.itemCount}'),
        if (r.reportNotes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Notes: ${r.reportNotes}'),
        ],
        const SizedBox(height: 24),
        if (canApprove)
          Row(children: [
            Expanded(child: FilledButton(
              onPressed: () => _decide(context, ref, true),
              child: const Text('Approve'))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton(
              onPressed: () => _decide(context, ref, false),
              child: const Text('Reject'))),
          ]),
      ]),
    );
  }
}
