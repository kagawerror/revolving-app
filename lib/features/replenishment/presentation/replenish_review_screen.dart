import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/replenishment.dart';
import 'replenishment_providers.dart';

class ReplenishReviewScreen extends ConsumerStatefulWidget {
  final Replenishment draft;
  const ReplenishReviewScreen({super.key, required this.draft});
  @override
  ConsumerState<ReplenishReviewScreen> createState() => _State();
}

class _State extends ConsumerState<ReplenishReviewScreen> {
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    setState(() => _busy = true);
    final res = await ref.read(replenishmentRepositoryProvider).submit(
        replenishment: widget.draft, actorUid: user.uid, notes: _notes.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.showOnError(context)) Navigator.of(context).pop();
  }

  Future<void> _discard() async {
    setState(() => _busy = true);
    final res = await ref.read(replenishmentRepositoryProvider)
        .discardDraft(replenishment: widget.draft);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.showOnError(context)) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return Scaffold(
      appBar: AppBar(title: const Text('Replenishment report')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(children: [
          Text('Items: ${d.itemCount}', style: Theme.of(context).textTheme.titleMedium),
          Text('Total: ${d.total.format()}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text('Submit for approval'),
          ),
          TextButton(onPressed: _busy ? null : _discard, child: const Text('Discard')),
        ]),
      ),
    );
  }
}
