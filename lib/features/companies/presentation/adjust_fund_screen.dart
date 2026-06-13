import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/fund.dart';
import 'admin_company_context_bar.dart';
import 'admin_providers.dart';
import 'adjust_fund_dialog.dart';

/// CEO/Admin entry into the Fund Adjustment workflow (`/approvals/adjust-fund`).
///
/// A CEO lands on the `/approvals` shell scoped to their own company, so this
/// screen lists that company's funds and lets them tap one to open the
/// [showAdjustFundDialog]. An admin (no fixed company) sees every fund and may
/// switch operating company via the [CompanyContextBar] at the top — mirroring
/// the other approval-subtree screens.
///
/// Role-gated to `canAdjustFund` (admin || ceo) in the router; this screen also
/// fails safe with its own guard so it can never render its actions for a role
/// that wandered in.
class AdjustFundScreen extends ConsumerWidget {
  const AdjustFundScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adjust fund')),
      body: const Column(
        children: [
          // Admin-only operating-company picker; renders nothing for a CEO.
          CompanyContextBar(),
          Expanded(child: _AdjustFundBody()),
        ],
      ),
    );
  }
}

class _AdjustFundBody extends ConsumerWidget {
  const _AdjustFundBody();

  Future<void> _open(BuildContext context, WidgetRef ref, Fund fund) async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;

    final done = await showAdjustFundDialog(
      context,
      fund: fund,
      onSubmit: (s) async {
        final res = await ref.read(fundRepositoryProvider).adjustBalance(
              fundId: fund.id,
              signedDeltaCentavos: s.signedDeltaCentavos,
              reason: s.reason,
              actorUid: me.uid,
              actorRole: me.role,
            );
        if (!context.mounted) return false;
        return res.showOnError(context); // true on Ok, snackbar on Err
      },
    );

    if (done != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            done.isDeduction
                ? 'Deducted ${done.amount.format()} from ${fund.name}'
                : 'Added ${done.amount.format()} to ${fund.name}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider).valueOrNull;

    // Fail-safe role guard (router already gates, but never render the money
    // surface for a role that can't adjust).
    if (me != null && !me.role.canAdjustFund) {
      return const EmptyState(
        title: 'Not available',
        message: 'You don’t have permission to adjust funds.',
        showMascot: false,
      );
    }

    // Admin: every fund, optionally narrowed to the operating company chosen in
    // the context bar. CEO: just their own company's funds.
    final isAdmin = me?.role.isAdmin ?? false;
    final activeCompanyId =
        isAdmin ? ref.watch(adminActiveCompanyProvider) : me?.companyId;

    final fundsAsync = isAdmin && activeCompanyId == null
        ? ref.watch(allFundsProvider)
        : ref.watch(companyFundsProvider(activeCompanyId ?? ''));

    return fundsAsync.when(
      loading: () => const _ListSkeleton(),
      error: (_, _) => _InlineError(
        onRetry: () => isAdmin && activeCompanyId == null
            ? ref.invalidate(allFundsProvider)
            : ref.invalidate(companyFundsProvider(activeCompanyId ?? '')),
      ),
      data: (funds) {
        if (funds.isEmpty) {
          return const EmptyState(
            title: 'No funds to adjust',
            message: 'Funds appear here once a company has them. '
                'Pick a company above, or ask an admin to create one.',
            showMascot: false,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppTokens.lg),
          children: [
            Text(
              'Pick a fund to add or deduct available cash. '
              'The fund’s budget stays the same.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppTokens.lg),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.sm,
                vertical: AppTokens.xs,
              ),
              child: Column(
                children: [
                  for (var i = 0; i < funds.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        indent: AppTokens.md,
                        endIndent: AppTokens.md,
                      ),
                    _FundRow(
                      fund: funds[i],
                      onTap: () => _open(context, ref, funds[i]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppTokens.bottomNavContentInset),
          ],
        ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.04, end: 0);
      },
    );
  }
}

/// A tappable fund row showing its name, budget, and live available balance
/// (red when low), with a "tune" affordance signalling the adjust action.
class _FundRow extends StatelessWidget {
  const _FundRow({required this.fund, required this.onTap});

  final Fund fund;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final low = fund.isLow;

    return AppListTile(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: AppTokens.brField,
        ),
        child: Icon(
          Icons.account_balance_wallet_rounded,
          color: scheme.onPrimaryContainer,
          semanticLabel: 'Fund',
        ),
      ),
      title: fund.name,
      subtitle: 'Budget ${fund.originalBudget.format()}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Semantics(
              label: 'Available balance ${fund.availableBalance.format()}',
              child: Text(
                fund.availableBalance.format(),
                maxLines: 1,
                textAlign: TextAlign.right,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: low ? scheme.error : scheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.sm),
          Icon(Icons.tune_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppTokens.lg),
      children: [
        Skeleton.line(width: 220),
        const SizedBox(height: AppTokens.lg),
        const SurfaceCard(child: SkeletonList(count: 4)),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTokens.lg),
      child: EmptyState(
        title: 'Couldn’t load funds',
        message: 'Something went wrong while loading funds.',
        showMascot: false,
        action: FilledButton.tonalIcon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ),
    );
  }
}
