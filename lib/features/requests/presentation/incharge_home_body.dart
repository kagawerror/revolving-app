import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/success_overlay.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/fund.dart';
import '../../companies/presentation/admin_active_company.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../../companies/presentation/admin_providers.dart';
import '../../../core/money/money.dart';
import '../../notifications/presentation/low_balance_banner.dart';
import '../../replenishment/presentation/replenish_select_dialog.dart';
import '../../replenishment/presentation/replenishment_providers.dart';
import '../../sync/presentation/pending_sync_indicator.dart';
import '../domain/fund_request.dart';
import '../domain/request_breakdown.dart';
import '../domain/request_status.dart';
import 'conflict_worklist_providers.dart';
import 'release_flow_controller.dart';
import 'request_detail_screen.dart';
import 'request_providers.dart';
import 'request_status_visual.dart';
import 'widgets/request_breakdown_view.dart';

/// Requests under a single fund. Keyed by (companyId, fundId) so the query is
/// company-scoped for the sameCompany read rule — a fundId-only query is
/// rejected with permission-denied on the device.
final _fundRequestsProvider =
    StreamProvider.family((ref, (String, String) key) =>
        ref.watch(requestRepositoryProvider).watchByFund(key.$1, key.$2));

/// Body of the incharge landing tab: the scrolling per-fund request list for the
/// resolved company. Body-only — the [RoleShellScreen] owns the Scaffold,
/// AppBar, [CompanyContextBar], bottom navigation, and the "New request" FAB.
class InchargeHomeBody extends ConsumerWidget {
  const InchargeHomeBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    return user == null
        ? const Center(child: CircularProgressIndicator())
        : _InchargeBody(user: user);
  }
}

/// The scrolling fund list for the resolved company. For an admin with no
/// company selected yet it shows [AdminSelectCompanyPrompt] instead of funds.
class _InchargeBody extends ConsumerWidget {
  const _InchargeBody({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyId =
        effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));
    // Admin superuser hasn't picked a company yet: prompt instead of an empty
    // list. Non-admins always have a non-empty companyId, so never see this.
    if (companyId.isEmpty) return const AdminSelectCompanyPrompt();

    // Offline banner + conflicts entry sit ABOVE the fund list so they're
    // visible regardless of the funds async state. The banner self-collapses
    // when online; the conflicts entry self-hides when there are no conflicts.
    return Column(
      children: [
        const OfflineBanner(),
        const _ConflictsEntry(),
        Expanded(
          child: ref.watch(companyFundsProvider(companyId)).when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppTokens.lg),
                  child: SurfaceCard(child: SkeletonList()),
                ),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (funds) => Column(
                  children: [
                    LowBalanceBanner(funds: funds),
                    Expanded(
                child: funds.isEmpty
                    ? const EmptyState(
                        title: 'No funds yet',
                        message: 'Once an admin sets up a fund for your '
                            'company, it will appear here.',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppTokens.lg,
                          AppTokens.md,
                          AppTokens.lg,
                          AppTokens.bottomNavContentInset,
                        ),
                        children: [
                          for (final f in funds)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppTokens.lg),
                              child: _FundSection(fund: f),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ),
      ],
    );
  }
}

/// A discoverable entry to the incharge "Conflicts" worklist. Self-hides when
/// there are no conflicts (zero chrome at rest); when one or more overdraft
/// conflicts exist it surfaces a calm-but-urgent card — a conflict is money in
/// limbo, so it must be impossible to miss. Tapping opens `/incharge/conflicts`.
class _ConflictsEntry extends ConsumerWidget {
  const _ConflictsEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref.watch(conflictsProvider).valueOrNull ?? const [];
    if (conflicts.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (bg, fg) = StatusPill.colorsFor(StatusTone.danger, scheme);
    final n = conflicts.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.lg, AppTokens.md, AppTokens.lg, 0),
      child: SurfaceCard(
        padding: const EdgeInsets.all(AppTokens.md),
        onTap: () => context.push('/incharge/conflicts'),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration:
                  BoxDecoration(color: bg, borderRadius: AppTokens.brField),
              child: Icon(Icons.error_outline_rounded, color: fg, size: 22),
            ),
            const SizedBox(width: AppTokens.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n == 1
                        ? '1 release needs resolving'
                        : '$n releases need resolving',
                    style: textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'These overdrew the fund on sync. Tap to re-release or void.',
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _FundSection extends ConsumerStatefulWidget {
  final Fund fund;
  const _FundSection({required this.fund});

  @override
  ConsumerState<_FundSection> createState() => _FundSectionState();
}

class _FundSectionState extends ConsumerState<_FundSection> {
  bool _busy = false;

  Future<void> _replenish(String uid) async {
    setState(() => _busy = true);
    try {
      final all = ref
              .read(_fundRequestsProvider(
                  (widget.fund.companyId, widget.fund.id)))
              .valueOrNull ??
          const <FundRequest>[];
      final releasable = all
          .where((r) =>
              r.status == RequestStatus.released && r.remaining.centavos > 0)
          .toList();
      if (!mounted) return;
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ReplenishSelectDialog(
          fund: widget.fund,
          releasable: releasable,
        ),
      );
      if (ok == true && mounted) {
        await SuccessOverlay.show(context, 'Submitted for approval');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fund = widget.fund;
    final requests =
        ref.watch(_fundRequestsProvider((fund.companyId, fund.id)));
    // Submitted-but-not-approved partial totals per request, derived from the
    // existing pending-replenishments stream (no extra Firestore read). Watched
    // once here, then the per-request Money is passed down to each row.
    final pendingByRequest = ref.watch(pendingPartialByRequestProvider);
    final user = ref.read(currentUserProvider).valueOrNull;
    final canReplenish = (user?.role.canManageFundOrAdmin ?? false) &&
        fund.status != FundStatus.replenishing;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fund header: name, balance, replenish action.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTokens.sm, AppTokens.sm, AppTokens.xs, AppTokens.xs),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: AppTokens.brField,
                  ),
                  child: Icon(Icons.account_balance_wallet_rounded,
                      color: scheme.onPrimaryContainer, size: 22),
                ),
                const SizedBox(width: AppTokens.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fund.name,
                          style: textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        '${fund.availableBalance.format()} available',
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (canReplenish)
                  TextButton.icon(
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Replenish'),
                    onPressed: _busy ? null : () => _replenish(user!.uid),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.xs),
          requests.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppTokens.sm),
              child: SkeletonList(count: 2),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppTokens.sm),
              child: Text('Error: $e'),
            ),
            data: (list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.sm, vertical: AppTokens.md),
                    child: Row(
                      children: [
                        Icon(Icons.inbox_rounded,
                            size: 20, color: scheme.onSurfaceVariant),
                        const SizedBox(width: AppTokens.sm),
                        Text('No requests yet',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      for (final r in list)
                        AppListTile(
                          title: r.beneficiaryName,
                          subtitle: r.purpose,
                          trailing: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              RequestBreakdownView(
                                breakdown: computeRequestBreakdown(
                                  r,
                                  pendingPartial: pendingByRequest[r.id] ??
                                      Money.zero,
                                ),
                                compact: true,
                              ),
                              const SizedBox(height: AppTokens.xs),
                              _RequestAction(request: r),
                            ],
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RequestDetailScreen(request: r),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 280.ms).moveY(begin: 8, end: 0, duration: 280.ms);
  }
}

class _RequestAction extends ConsumerWidget {
  final FundRequest request;
  const _RequestAction({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.read(currentUserProvider).valueOrNull;
    // Defense-in-depth: an incharge custodian (or an admin superuser operating
    // this company) may release/ready requests — mirrors the isIncharge() ||
    // isAdmin() Firestore rule. Otherwise show the status pill.
    final canManage = user?.role.canManageFundOrAdmin ?? false;
    if (!canManage) return _statusPill();
    switch (request.status) {
      // Release-first: the incharge releases a freshly created request directly.
      // A conflicted (overdraft) request is resolved through the same release
      // flow once funds allow.
      case RequestStatus.created:
      case RequestStatus.conflict:
        return FilledButton.icon(
          onPressed: () => unawaited(ref
              .read(releaseFlowControllerProvider.notifier)
              .run(context, request, user!.uid)),
          icon: const Icon(Icons.payments_rounded, size: 18),
          label: const Text('Release'),
        );
      default:
        return _statusPill();
    }
  }

  Widget _statusPill() {
    final visual = requestStatusVisual(request.status);
    return StatusPill(
      label: visual.label,
      tone: visual.tone,
      icon: visual.icon,
    );
  }
}
