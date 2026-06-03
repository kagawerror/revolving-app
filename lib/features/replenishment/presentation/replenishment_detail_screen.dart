import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/replenishment.dart';
import 'replenishment_providers.dart';

class ReplenishmentDetailScreen extends ConsumerStatefulWidget {
  final Replenishment replenishment;
  const ReplenishmentDetailScreen({super.key, required this.replenishment});

  @override
  ConsumerState<ReplenishmentDetailScreen> createState() =>
      _ReplenishmentDetailScreenState();
}

class _ReplenishmentDetailScreenState
    extends ConsumerState<ReplenishmentDetailScreen> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    setState(() => _busy = true);
    final repo = ref.read(replenishmentRepositoryProvider);
    final res = approve
        ? await repo.approve(
            replenishment: widget.replenishment, actorUid: user.uid)
        : await repo.reject(
            replenishment: widget.replenishment, actorUid: user.uid);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.showOnError(context)) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canApprove =
        ref.watch(currentUserProvider).valueOrNull?.role.canApprove ?? false;
    final r = widget.replenishment;
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
        if (_busy)
          const Center(child: Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: CircularProgressIndicator(),
          )),
        if (canApprove)
          Row(children: [
            Expanded(child: FilledButton(
              onPressed: _busy ? null : () => _decide(true),
              child: const Text('Approve'))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton(
              onPressed: _busy ? null : () => _decide(false),
              child: const Text('Reject'))),
          ]),
      ]),
    );
  }
}
