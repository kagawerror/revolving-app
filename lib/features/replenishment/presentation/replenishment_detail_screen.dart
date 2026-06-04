import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/success_overlay.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/replenishment.dart';
import 'replenishment_providers.dart';
import 'replenishment_status_ui.dart';

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
    if (res.showOnError(context)) {
      // Celebrate the sign-off, then complete the existing pop. The overlay
      // awaits its own dismissal, so the pop-on-success behavior is preserved.
      await SuccessOverlay.show(
          context, approve ? 'Replenishment approved' : 'Replenishment rejected');
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canApprove =
        ref.watch(currentUserProvider).valueOrNull?.role.canApprove ?? false;
    final r = widget.replenishment;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ids = r.requestIds;

    return Scaffold(
      appBar: AppBar(title: const Text('Replenishment')),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.lg),
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total',
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    StatusPill(
                      label: replenishmentStatusLabel(r.status),
                      tone: replenishmentStatusTone(r.status),
                      icon: replenishmentStatusIcon(r.status),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.xs),
                Text(
                  r.total.format(),
                  style: textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppTokens.sm),
                Text(
                  '${r.itemCount} bundled ${r.itemCount == 1 ? 'request' : 'requests'}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (r.reportNotes.isNotEmpty) ...[
                  const SizedBox(height: AppTokens.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppTokens.md),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: AppTokens.brField,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notes',
                          style: textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppTokens.xs),
                        Text(r.reportNotes, style: textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.06, end: 0),
          const SectionHeader(title: 'Released requests'),
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
          const SizedBox(height: AppTokens.xl),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: AppTokens.lg),
                child: CircularProgressIndicator(),
              ),
            ),
          if (canApprove)
            Row(children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _decide(true),
                  child: const Text('Approve'),
                ),
              ),
              const SizedBox(width: AppTokens.md),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _decide(false),
                  child: const Text('Reject'),
                ),
              ),
            ]),
        ],
      ),
    );
  }
}
