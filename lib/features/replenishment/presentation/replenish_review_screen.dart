import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/balance_hero_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/success_overlay.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/replenishment.dart';
import 'replenishment_providers.dart';
import 'replenishment_status_ui.dart';

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
    if (res.showOnError(context)) {
      // Show the celebratory moment, then complete the existing pop. The
      // overlay awaits its own dismissal, so navigation behavior (pop on
      // success) is preserved exactly.
      await SuccessOverlay.show(context, 'Submitted for approval');
      if (!mounted) return;
      Navigator.of(context).pop();
    }
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
    final seed = ref.watch(themeControllerProvider).seed;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ids = d.requestIds;

    return Scaffold(
      appBar: AppBar(title: const Text('Replenishment report')),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.lg),
        children: [
          BalanceHeroCard(
            seed: seed,
            primaryLabel: 'Replenishment total',
            primaryAmount: d.total.format(),
            secondaryLabel: 'Bundled requests',
            secondaryAmount: '${d.itemCount}',
          ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.08, end: 0),
          SectionHeader(
            title: 'Released requests',
            trailing: StatusPill(
              label: replenishmentStatusLabel(d.status),
              tone: replenishmentStatusTone(d.status),
              icon: replenishmentStatusIcon(d.status),
            ),
          ),
          if (ids.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppTokens.xl),
              child: EmptyState(
                title: 'No requests bundled',
                message: 'This report has no released requests to replenish.',
              ),
            )
          else
            ...List.generate(ids.length, (i) {
              return AppListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    '${i + 1}',
                    style: textTheme.labelLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: 'Request #${i + 1}',
                subtitle: ids[i],
              ).animate(delay: (40 * i).ms).fadeIn(duration: 220.ms);
            }),
          const SizedBox(height: AppTokens.lg),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 3,
          ),
          const SizedBox(height: AppTokens.xl),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit for approval'),
          ),
          const SizedBox(height: AppTokens.sm),
          TextButton(onPressed: _busy ? null : _discard, child: const Text('Discard')),
        ],
      ),
    );
  }
}
