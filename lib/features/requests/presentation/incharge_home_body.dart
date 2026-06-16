import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/success_overlay.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/fund.dart';
import '../../companies/presentation/admin_active_company.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../../dashboard/presentation/dashboard_providers.dart' show companyNamesProvider;
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
import 'visible_funds_providers.dart';
import 'widgets/request_breakdown_view.dart';

/// Requests under a single fund. Keyed by (companyId, fundId) so the query is
/// company-scoped for the sameCompany read rule — a fundId-only query is
/// rejected with permission-denied on the device.
final _fundRequestsProvider = StreamProvider.family(
  (ref, (String, String) key) =>
      ref.watch(requestRepositoryProvider).watchByFund(key.$1, key.$2),
);

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
    final companyId = effectiveCompanyId(
      user,
      ref.watch(adminActiveCompanyProvider),
    );
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
          child: ref
              .watch(inchargeVisibleFundsProvider(companyId))
              .when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppTokens.lg),
                  child: SurfaceCard(child: SkeletonList()),
                ),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (visible) {
                  final funds = visible.funds;
                  // Strict empty state for an incharge with no assigned funds —
                  // distinct from "no funds exist". Never shown for an admin
                  // superuser (unscoped), who falls through to the list/banner.
                  if (visible.isEmptyState) {
                    return const EmptyState(
                      title: 'No funds assigned',
                      message:
                          'You don’t have any funds yet. Ask your admin to '
                          'assign one to you, then it’ll show up here.',
                      showMascot: true,
                    );
                  }
                  return Column(
                    children: [
                      LowBalanceBanner(funds: funds),
                      Expanded(
                        child: funds.isEmpty
                            ? const EmptyState(
                                title: 'No funds yet',
                                message:
                                    'Once an admin sets up a fund for your '
                                    'company, it will appear here.',
                              )
                            : _GroupedFundList(
                                funds: funds,
                                companyNames:
                                    ref.watch(companyNamesProvider),
                              ),
                      ),
                    ],
                  );
                },
              ),
        ),
      ],
    );
  }
}

/// The scoped fund list, grouped by owning company. Companies are sorted by
/// name (then funds by name within each), so the order is stable and readable
/// for an incharge whose funds span multiple companies. A [SectionHeader] is
/// shown per company ONLY when 2+ companies are present — a single-company
/// incharge sees a clean ungrouped list (the company name still rides as the
/// overline on each fund card via [_FundSection]).
class _GroupedFundList extends StatelessWidget {
  const _GroupedFundList({required this.funds, required this.companyNames});

  final List<Fund> funds;
  final Map<String, String> companyNames;

  String _nameFor(String companyId) =>
      companyNames[companyId] ?? 'Unknown company';

  @override
  Widget build(BuildContext context) {
    // Group by companyId, preserving the input (name-sorted) fund order within
    // each group via insertion order.
    final byCompany = <String, List<Fund>>{};
    for (final f in funds) {
      (byCompany[f.companyId] ??= []).add(f);
    }
    // Sort funds within each company by name.
    for (final list in byCompany.values) {
      list.sort((a, b) => a.name.compareTo(b.name));
    }
    // Sort companies by display name (then id, for stability on equal names).
    final companyIds = byCompany.keys.toList()
      ..sort((a, b) {
        final byName = _nameFor(a).compareTo(_nameFor(b));
        return byName != 0 ? byName : a.compareTo(b);
      });
    final showHeaders = companyIds.length >= 2;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.lg,
        AppTokens.md,
        AppTokens.lg,
        AppTokens.bottomNavContentInset,
      ),
      children: [
        for (final companyId in companyIds) ...[
          if (showHeaders) SectionHeader(title: _nameFor(companyId)),
          for (final f in byCompany[companyId]!)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.lg),
              child: _FundSection(
                fund: f,
                companyName: _nameFor(companyId),
              ),
            ),
        ],
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
        AppTokens.lg,
        AppTokens.md,
        AppTokens.lg,
        0,
      ),
      child: SurfaceCard(
        padding: const EdgeInsets.all(AppTokens.md),
        onTap: () => context.push('/incharge/conflicts'),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: AppTokens.brField,
              ),
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
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'These overdrew the fund on sync. Tap to re-release or void.',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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

  /// Owning-company display name, shown as an uppercase overline above the fund
  /// name — matches the dashboard `_FundCard` treatment so the same fund reads
  /// the same everywhere. Null/empty hides the overline (e.g. names not loaded).
  final String? companyName;

  const _FundSection({required this.fund, this.companyName});

  @override
  ConsumerState<_FundSection> createState() => _FundSectionState();
}

class _FundSectionState extends ConsumerState<_FundSection> {
  bool _busy = false;

  Future<void> _replenish(String uid) async {
    setState(() => _busy = true);
    try {
      final all =
          ref
              .read(
                _fundRequestsProvider((widget.fund.companyId, widget.fund.id)),
              )
              .valueOrNull ??
          const <FundRequest>[];
      // Release-first: released cash may already be acknowledged/disputed by an
      // approver yet still owed back to the fund, so all replenishable statuses
      // belong in the sheet — not just `released`.
      final releasable = all
          .where((r) => r.status.isReplenishable && r.remaining.centavos > 0)
          .toList();
      if (!mounted) return;
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            ReplenishSelectDialog(fund: widget.fund, releasable: releasable),
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
    final requests = ref.watch(
      _fundRequestsProvider((fund.companyId, fund.id)),
    );
    // Submitted-but-not-approved partial totals per request, derived from the
    // existing pending-replenishments stream (no extra Firestore read). Watched
    // once here, then the per-request Money is passed down to each row.
    final pendingByRequest = ref.watch(pendingPartialByRequestProvider);
    final user = ref.read(currentUserProvider).valueOrNull;
    final canReplenish =
        (user?.role.canManageFundOrAdmin ?? false) &&
        fund.status != FundStatus.replenishing;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fund header: name, balance, replenish action.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.sm,
              AppTokens.sm,
              AppTokens.xs,
              AppTokens.xs,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: AppTokens.brField,
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    color: scheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppTokens.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.companyName != null &&
                          widget.companyName!.isNotEmpty)
                        Text(
                          widget.companyName!.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      Text(
                        fund.name,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${fund.availableBalance.format()} available',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
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
            data: (rawList) {
              // Hide fully-finished requests (replenished/rejected) from the
              // active fund worklist — they still appear in reports + detail.
              final list = rawList.where((r) => r.isActiveInFund).toList();
              return list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.sm,
                        vertical: AppTokens.md,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.inbox_rounded,
                            size: 20,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppTokens.sm),
                          Text(
                            'No requests yet',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0)
                            const Divider(
                              height: 1,
                              indent: AppTokens.md,
                              endIndent: AppTokens.md,
                            ),
                          AppListTile(
                            title: list[i].beneficiaryName,
                            subtitle: list[i].purpose,
                            trailing: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                RequestBreakdownView(
                                  breakdown: computeRequestBreakdown(
                                    list[i],
                                    pendingPartial:
                                        pendingByRequest[list[i].id] ??
                                        Money.zero,
                                  ),
                                  compact: true,
                                ),
                                const SizedBox(height: AppTokens.xs),
                                _RequestAction(request: list[i]),
                              ],
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    RequestDetailScreen(request: list[i]),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
            },
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
          onPressed: () => unawaited(
            ref
                .read(releaseFlowControllerProvider.notifier)
                .run(context, request, user!.uid),
          ),
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
