import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/fund.dart';
import '../../companies/presentation/admin_active_company.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../../companies/presentation/admin_providers.dart';
import '../../notifications/presentation/low_balance_banner.dart';
import '../../replenishment/presentation/replenish_review_screen.dart';
import '../../replenishment/presentation/replenishment_providers.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'request_detail_screen.dart';
import 'request_providers.dart';
import 'request_status_visual.dart';

/// Requests under a single fund. Keyed by (companyId, fundId) so the query is
/// company-scoped for the sameCompany read rule — a fundId-only query is
/// rejected with permission-denied on the device.
final _fundRequestsProvider =
    StreamProvider.family((ref, (String, String) key) =>
        ref.watch(requestRepositoryProvider).watchByFund(key.$1, key.$2));

/// Compiles a replenishment draft for [fundId], then opens the review screen.
Future<void> _startReplenish(
    BuildContext context, WidgetRef ref, String fundId, String uid) async {
  final res = await ref
      .read(replenishmentRepositoryProvider)
      .createDraft(fundId: fundId, createdByUid: uid);
  if (!context.mounted) return;
  final draft = res.valueOrNull;
  if (draft == null) {
    context.showFailure(res.failureOrNull!);
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReplenishReviewScreen(draft: draft)));
}

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

    return ref.watch(companyFundsProvider(companyId)).when(
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
      await _startReplenish(context, ref, widget.fund.id, uid);
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
                              Text(
                                r.amount.format(),
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
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
    final repo = ref.read(requestRepositoryProvider);
    final user = ref.read(currentUserProvider).valueOrNull;
    // Defense-in-depth: an incharge custodian (or an admin superuser operating
    // this company) may release/ready requests — mirrors the isIncharge() ||
    // isAdmin() Firestore rule. Otherwise show the status pill.
    final canManage = user?.role.canManageFundOrAdmin ?? false;
    if (!canManage) return _statusPill();
    switch (request.status) {
      case RequestStatus.acknowledged:
        return FilledButton.tonalIcon(
          onPressed: () async {
            final res = await repo.transition(
              request: request,
              to: RequestStatus.readyForRelease,
              actorUid: user!.uid,
            );
            if (context.mounted) res.showOnError(context);
          },
          icon: const Icon(Icons.task_alt_rounded, size: 18),
          label: const Text('Mark ready'),
        );
      case RequestStatus.readyForRelease:
        return FilledButton.icon(
          onPressed: () async {
            final res =
                await repo.release(request: request, actorUid: user!.uid);
            if (context.mounted) res.showOnError(context);
          },
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
