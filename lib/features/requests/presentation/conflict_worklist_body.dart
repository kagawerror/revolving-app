import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/money/signed_money_text.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../sync/domain/optimistic_balance.dart';
import '../../sync/presentation/sync_providers.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'conflict_worklist_providers.dart';
import 'request_detail_screen.dart';
import 'request_providers.dart';

/// Body of the incharge "Conflicts" worklist: requests in `conflict` status —
/// offline releases that overdrew the fund when they synced. Body-only, so it
/// can live under the existing role shell tab OR a standalone screen (the host
/// owns the Scaffold / AppBar / CompanyContextBar), matching every other
/// worklist body in this feature.
///
/// Tone: this is money in dispute, so the surface stays SERIOUS but CALM — the
/// theme's error-container tones are used sparingly (a single leading glyph +
/// the negative amount), never a full red panel. The three async surfaces match
/// the app: shimmer skeleton / reassuring empty / error-with-retry.
class ConflictWorklistBody extends ConsumerWidget {
  const ConflictWorklistBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(conflictsProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppTokens.lg),
        child: SurfaceCard(child: SkeletonList(count: 3)),
      ),
      error: (e, _) =>
          _ConflictError(onRetry: () => ref.invalidate(conflictsProvider)),
      data: (requests) => requests.isEmpty
          ? const _ConflictEmpty()
          : _ConflictList(requests: requests),
    );
  }
}

class _ConflictEmpty extends StatelessWidget {
  const _ConflictEmpty();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      title: 'No conflicts',
      message: 'All releases synced cleanly. If an offline release ever '
          'overdraws a fund when it reaches the server, it will show up here '
          'for you to resolve.',
    );
  }
}

class _ConflictError extends StatelessWidget {
  const _ConflictError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
            const SizedBox(height: AppTokens.lg),
            Text('Couldn’t load conflicts',
                textAlign: TextAlign.center,
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppTokens.sm),
            Text('Check your connection and try again.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: AppTokens.xl),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictList extends StatelessWidget {
  const _ConflictList({required this.requests});
  final List<FundRequest> requests;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppTokens.lg, AppTokens.md,
          AppTokens.lg, AppTokens.bottomNavContentInset),
      children: [
        // A single calm explainer at the top — sets context once so each row
        // doesn't have to shout. tertiaryContainer reads as "noteworthy" rather
        // than "error".
        Container(
          padding: const EdgeInsets.all(AppTokens.md),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: AppTokens.brCard,
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: scheme.onTertiaryContainer),
              const SizedBox(width: AppTokens.md),
              Expanded(
                child: Text(
                  'These releases overdrew the fund when they synced. The cash '
                  'was already handed out — resolve each by re-releasing once '
                  'the balance can cover it, or voiding it.',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onTertiaryContainer),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.md),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.xs),
          child: Column(
            children: [
              for (var i = 0; i < requests.length; i++) ...[
                if (i > 0)
                  const Divider(
                      height: 1,
                      indent: AppTokens.md,
                      endIndent: AppTokens.md),
                _ConflictRow(
                    key: ValueKey(requests[i].id), request: requests[i]),
              ],
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 280.ms).moveY(begin: 8, end: 0, duration: 280.ms);
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({super.key, required this.request});
  final FundRequest request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (bg, fg) = StatusPill.colorsFor(StatusTone.danger, scheme);

    return AppListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: bg, borderRadius: AppTokens.brField),
        child: Icon(Icons.error_outline_rounded, color: fg, size: 22),
      ),
      title: request.beneficiaryName,
      subtitle: 'Overdrew fund on sync · ${request.purpose}',
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            request.amount.format(),
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppTokens.xs),
          const StatusPill(
            label: 'Resolve',
            tone: StatusTone.danger,
            icon: Icons.priority_high_rounded,
          ),
        ],
      ),
      onTap: () => ConflictResolutionSheet.show(context, request),
    );
  }
}

/// The resolution sheet for one conflict. Surfaces the full context (amount,
/// payee, purpose, fund) and a live read of whether the CURRENT optimistic
/// balance can now cover a re-release, then offers two actions — each behind its
/// own confirmation dialog (hard requirement: every money/state decision is
/// confirmed):
///
///   • Re-release  → `resolveConflict(to: released)`. Re-runs the release
///     transaction, which re-validates the balance server-side. The button hints
///     whether funds now appear sufficient, but never blocks: the server is the
///     authority and a stale optimistic read shouldn't trap the incharge.
///   • Void this release → `resolveConflict(to: rejected)`. For cash that must
///     be written off or was a mistake.
class ConflictResolutionSheet extends ConsumerWidget {
  const ConflictResolutionSheet({super.key, required this.request});

  final FundRequest request;

  static Future<void> show(BuildContext context, FundRequest request) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ConflictResolutionSheet(request: request),
      );

  Future<void> _reRelease(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final confirmed = await _confirm(
      context,
      icon: Icons.payments_rounded,
      title: 'Re-release this cash?',
      body: 'This re-runs the release of ${request.amount.format()} to '
          '${request.beneficiaryName}. The fund balance is re-checked on the '
          'server — if it still can’t cover the amount, the request stays in '
          'conflict and no money moves.',
      confirmLabel: 'Re-release',
      destructive: false,
    );
    if (confirmed != true || !context.mounted) return;
    final res = await ref.read(requestRepositoryProvider).resolveConflict(
          request: request,
          to: RequestStatus.released,
          actorUid: user.uid,
        );
    if (!context.mounted) return;
    if (res.showOnError(context)) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
            const SnackBar(content: Text('Release re-confirmed')));
    }
  }

  Future<void> _void(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final confirmed = await _confirm(
      context,
      icon: Icons.block_rounded,
      title: 'Void this release?',
      body: 'This marks the ${request.amount.format()} release to '
          '${request.beneficiaryName} as rejected. Use this only when the cash '
          'is being written off or the release was a mistake. This cannot be '
          'undone.',
      confirmLabel: 'Void release',
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    final res = await ref.read(requestRepositoryProvider).resolveConflict(
          request: request,
          to: RequestStatus.rejected,
          actorUid: user.uid,
          // Display-only on the incharge's requestRejected alert. The sheet's
          // build already watches the fund (via optimisticFundBalanceProvider),
          // so it's warm here; null-safe if it somehow hasn't loaded.
          fundName: ref.read(fundByIdProvider(request.fundId)).valueOrNull?.name,
        );
    if (!context.mounted) return;
    if (res.showOnError(context)) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Release voided')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final balance = ref.watch(optimisticFundBalanceProvider(request.fundId));
    final canCover = !balance.isNegative &&
        balance.centavos >= request.amount.centavos;
    // Pre-warm the fund stream so its display-only name is already resolved when
    // _void threads it onto the incharge's requestRejected notification (read
    // null-safely there). Never gates the action.
    ref.watch(fundByIdProvider(request.fundId));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.rCard)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
              AppTokens.lg, AppTokens.md, AppTokens.lg, AppTokens.xl),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppTokens.rPill),
                ),
              ),
            ),
            const SizedBox(height: AppTokens.lg),
            // Headline: amount + the calm "Conflict" status pill.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Amount released',
                          style: textTheme.labelMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(
                        request.amount.format(),
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const StatusPill(
                  label: 'Conflict',
                  tone: StatusTone.danger,
                  icon: Icons.error_outline_rounded,
                ),
              ],
            ),
            const SizedBox(height: AppTokens.lg),
            _SheetDetail(
                icon: Icons.person_rounded,
                label: 'Paid to',
                value: request.beneficiaryName),
            const SizedBox(height: AppTokens.md),
            _SheetDetail(
                icon: Icons.notes_rounded,
                label: 'Purpose',
                value: request.purpose),
            const SizedBox(height: AppTokens.lg),

            // Live balance hint for re-release.
            _BalanceHint(balance: balance, canCover: canCover),

            const SizedBox(height: AppTokens.xl),
            FilledButton.icon(
              onPressed: () => _reRelease(context, ref),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(Icons.payments_rounded),
              label: Text(canCover
                  ? 'Re-release now'
                  : 'Re-release (re-checks balance)'),
            ),
            const SizedBox(height: AppTokens.sm),
            OutlinedButton.icon(
              onPressed: () => _void(context, ref),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error),
              ),
              icon: const Icon(Icons.block_rounded),
              label: const Text('Void this release'),
            ),
            const SizedBox(height: AppTokens.sm),
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => RequestDetailScreen(request: request)),
                ),
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                label: const Text('View full details'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live "can the fund cover this now?" hint. Reads the optimistic balance and
/// renders a success/warning chip-style row. Never gates the action — just
/// informs the decision.
class _BalanceHint extends StatelessWidget {
  const _BalanceHint({required this.balance, required this.canCover});

  final OptimisticBalance balance;
  final bool canCover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tone = canCover ? StatusTone.success : StatusTone.warning;
    final (bg, fg) = StatusPill.colorsFor(tone, scheme);
    final balanceText = formatSignedCentavos(balance.centavos);

    return Container(
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(color: bg, borderRadius: AppTokens.brField),
      child: Row(
        children: [
          Icon(canCover ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              color: fg),
          const SizedBox(width: AppTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  canCover
                      ? 'Balance can now cover this'
                      : 'Balance may not cover this yet',
                  style: textTheme.titleSmall
                      ?.copyWith(color: fg, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Available now: $balanceText',
                  style: textTheme.bodySmall?.copyWith(
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetDetail extends StatelessWidget {
  const _SheetDetail(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppTokens.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(value, style: textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shared confirmation dialog for both conflict actions — mirrors the
/// release-flow controller's AlertDialog voice (icon + plain consequence copy +
/// Cancel / primary). Destructive actions tint the confirm button to `error`.
Future<bool?> _confirm(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String body,
  required String confirmLabel,
  required bool destructive,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(icon),
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
