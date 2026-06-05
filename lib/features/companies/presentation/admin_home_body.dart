import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/company.dart';
import '../domain/fund.dart';
import 'add_company_dialog.dart';
import 'admin_providers.dart';
import 'edit_company_dialog.dart';
import 'edit_fund_dialog.dart';
import 'fund_grouping.dart';

/// Body of the admin landing tab: provisioned companies, funds, users, and the
/// operational entry points. Body-only — the [RoleShellScreen] owns the
/// Scaffold, AppBar (title + AlertsBell), bottom navigation, and the "New fund"
/// FAB. The data source (`companiesProvider`), dialog/callback logic, and routes
/// are preserved exactly from the former AdminHomeScreen.
class AdminHomeBody extends ConsumerWidget {
  const AdminHomeBody({super.key});

  Future<void> _handleAddCompany(BuildContext context, WidgetRef ref) async {
    final added = await showAddCompanyDialog(
      context,
      onSubmit: (name) async {
        final res = await ref.read(companyRepositoryProvider).create(name);
        if (!context.mounted) return false;
        return res.showOnError(context); // true on success, snackbar on error
      },
    );
    if (added != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Company added')));
    }
  }

  Future<void> _handleEditCompany(
    BuildContext context,
    WidgetRef ref,
    Company company,
  ) async {
    final saved = await showEditCompanyDialog(
      context,
      initialName: company.name,
      onSubmit: (name) async {
        final res =
            await ref.read(companyRepositoryProvider).update(company.id, name);
        if (!context.mounted) return false;
        return res.showOnError(context);
      },
    );
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company updated')),
      );
    }
  }

  Future<void> _handleEditFund(
    BuildContext context,
    WidgetRef ref,
    Fund fund,
  ) async {
    final actorUid = ref.read(currentUserProvider).valueOrNull?.uid ?? '';
    final saved = await showEditFundDialog(
      context,
      fund: fund,
      onSubmit: (s) async {
        final repo = ref.read(fundRepositoryProvider);
        // Budget change first: it shifts both budget and available balance by
        // the same delta and writes an audit entry.
        if (s.touchesBudget) {
          final res = await repo.adjustBudget(
            fundId: fund.id,
            newBudget: s.newBudget!,
            actorUid: actorUid,
            note: 'Admin budget edit',
          );
          if (!context.mounted || !res.showOnError(context)) return false;
        }
        if (s.touchesDetails) {
          final res = await repo.updateDetails(
            fundId: fund.id,
            name: s.name ?? fund.name,
            lowBalanceThresholdPct:
                s.lowBalanceThresholdPct ?? fund.lowBalanceThresholdPct,
          );
          if (!context.mounted || !res.showOnError(context)) return false;
        }
        return true;
      },
    );
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fund updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(companiesProvider);
    final fundsAsync = ref.watch(allFundsProvider);

    return companies.when(
      loading: () => const _AdminSkeleton(),
      error: (e, _) => _AdminError(message: 'Error: $e'),
      data: (list) => _AdminBody(
        companies: list,
        funds: fundsAsync.whenData(
          (funds) => groupFundsByCompany(funds, list),
        ),
        totalFundCount: fundsAsync.maybeWhen(
          data: (f) => f.length,
          orElse: () => 0,
        ),
        onRetryFunds: () => ref.invalidate(allFundsProvider),
        onAddCompany: () => _handleAddCompany(context, ref),
        onEditCompany: (c) => _handleEditCompany(context, ref, c),
        onEditFund: (f) => _handleEditFund(context, ref, f),
        onManageUsers: () => context.push('/admin/users'),
        onConfigureCloudinary: () => context.push('/admin/cloudinary'),
        onOperateIncharge: () => context.push('/incharge'),
        onOpenApprovals: () => context.push('/approvals'),
      ),
    );
  }
}

class _AdminBody extends StatelessWidget {
  const _AdminBody({
    required this.companies,
    required this.funds,
    required this.totalFundCount,
    required this.onRetryFunds,
    required this.onAddCompany,
    required this.onEditCompany,
    required this.onEditFund,
    required this.onManageUsers,
    required this.onConfigureCloudinary,
    required this.onOperateIncharge,
    required this.onOpenApprovals,
  });

  final List<Company> companies;
  final AsyncValue<
    List<({String companyId, String companyName, List<Fund> funds})>
  >
  funds;
  final int totalFundCount;
  final VoidCallback onRetryFunds;
  final VoidCallback onAddCompany;
  final ValueChanged<Company> onEditCompany;
  final ValueChanged<Fund> onEditFund;
  final VoidCallback onManageUsers;
  final VoidCallback onConfigureCloudinary;
  final VoidCallback onOperateIncharge;
  final VoidCallback onOpenApprovals;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppTokens.lg),
      children: [
        const _AdminHero(),
        const SizedBox(height: AppTokens.lg),
        _OperationsSection(
          onOperateIncharge: onOperateIncharge,
          onOpenApprovals: onOpenApprovals,
        ),
        const SizedBox(height: AppTokens.lg),
        SectionHeader(
          title: 'Companies',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CountBadge(companies.length),
              const SizedBox(width: AppTokens.sm),
              TextButton.icon(
                onPressed: onAddCompany,
                icon: const Icon(Icons.add_business_rounded, size: 20),
                label: const Text('Add company'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: AppTokens.md),
                ),
              ),
            ],
          ),
        ),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.sm,
            vertical: AppTokens.xs,
          ),
          child: companies.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppTokens.lg),
                  child: EmptyState(
                    title: 'No companies yet',
                    message:
                        'Add a company first, then create a fund for it. '
                        'Provisioned companies will appear here.',
                    showMascot: false,
                    action: FilledButton.icon(
                      onPressed: onAddCompany,
                      icon: const Icon(Icons.add_business_rounded),
                      label: const Text('Add company'),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < companies.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          indent: AppTokens.md,
                          endIndent: AppTokens.md,
                        ),
                      _CompanyTile(
                        company: companies[i],
                        onEdit: () => onEditCompany(companies[i]),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: AppTokens.lg),
        _FundsSection(
          funds: funds,
          totalCount: totalFundCount,
          onRetry: onRetryFunds,
          onEditFund: onEditFund,
        ),
        const SizedBox(height: AppTokens.lg),
        _UsersSection(onManage: onManageUsers),
        const SizedBox(height: AppTokens.lg),
        _SystemSection(onConfigureCloudinary: onConfigureCloudinary),
        // Bottom breathing room so the FAB + bottom nav never cover the last row.
        const SizedBox(height: AppTokens.bottomNavContentInset),
      ],
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.04, end: 0);
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({required this.company, required this.onEdit});

  final Company company;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: AppTokens.brField,
        ),
        child: Icon(
          Icons.business_rounded,
          color: scheme.onPrimaryContainer,
          semanticLabel: 'Company',
        ),
      ),
      title: company.name,
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined),
        tooltip: 'Edit company',
        onPressed: onEdit,
      ),
    );
  }
}

class _FundsSection extends StatelessWidget {
  const _FundsSection({
    required this.funds,
    required this.totalCount,
    required this.onRetry,
    required this.onEditFund,
  });
  final AsyncValue<
    List<({String companyId, String companyName, List<Fund> funds})>
  >
  funds;
  final int totalCount;
  final VoidCallback onRetry;
  final ValueChanged<Fund> onEditFund;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Funds',
          trailing: funds.maybeWhen(
            data: (_) => _CountBadge(totalCount),
            orElse: () => null,
          ),
        ),
        funds.when(
          loading: () => const SurfaceCard(
            padding: EdgeInsets.symmetric(
              horizontal: AppTokens.lg,
              vertical: AppTokens.lg,
            ),
            child: SkeletonList(count: 3),
          ),
          error: (e, _) => _FundsInlineError(onRetry: onRetry),
          data: (groups) {
            if (groups.isEmpty) {
              return const SurfaceCard(
                padding: EdgeInsets.symmetric(vertical: AppTokens.lg),
                child: EmptyState(
                  title: 'No funds yet',
                  message: 'Funds you create with “New fund” will appear here.',
                  showMascot: false,
                ),
              );
            }
            return SurfaceCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.sm,
                vertical: AppTokens.xs,
              ),
              child: Column(
                children: [
                  for (var g = 0; g < groups.length; g++) ...[
                    if (g > 0)
                      const Divider(
                        height: 1,
                        indent: AppTokens.md,
                        endIndent: AppTokens.md,
                      ),
                    _FundGroupHeader(
                      name: groups[g].companyName,
                      count: groups[g].funds.length,
                    ),
                    for (var i = 0; i < groups[g].funds.length; i++)
                      _FundTile(
                        fund: groups[g].funds[i],
                        onEdit: () => onEditFund(groups[g].funds[i]),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.04, end: 0);
  }
}

class _FundGroupHeader extends StatelessWidget {
  const _FundGroupHeader({required this.name, required this.count});
  final String name;
  final int count;
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.md,
        AppTokens.md,
        AppTokens.md,
        AppTokens.xs,
      ),
      child: Semantics(
        header: true,
        label: '$name, $count ${count == 1 ? 'fund' : 'funds'}',
        child: Row(
          children: [
            Icon(
              Icons.business_rounded,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppTokens.sm),
            Expanded(
              child: Text(
                name,
                style: textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FundTile extends StatelessWidget {
  const _FundTile({required this.fund, required this.onEdit});
  final Fund fund;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final low = fund.isLow;
    return AppListTile(
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
            constraints: const BoxConstraints(maxWidth: 132),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Semantics(
                  label: 'Available balance ${fund.availableBalance.format()}',
                  child: Text(
                    fund.availableBalance.format(),
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    textAlign: TextAlign.right,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: low ? scheme.error : scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.xs),
                _FundStatusChip(status: fund.status, isLow: low),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit fund',
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _FundStatusChip extends StatelessWidget {
  const _FundStatusChip({required this.status, required this.isLow});
  final FundStatus status;
  final bool isLow;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Flag "Low" if either the computed balance (Fund.isLow) OR the stored
    // status says so — they can disagree, and either is worth attention.
    final showLow = isLow || status == FundStatus.low;
    final (Color bg, Color fg, String label, IconData icon) = switch (status) {
      _ when showLow => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        'Low',
        Icons.warning_amber_rounded,
      ),
      FundStatus.replenishing => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        'Replenishing',
        Icons.sync_rounded,
      ),
      FundStatus.active || FundStatus.low => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        'Active',
        Icons.check_circle_rounded,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTokens.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: AppTokens.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FundsInlineError extends StatelessWidget {
  const _FundsInlineError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.lg),
      child: EmptyState(
        title: 'Couldn’t load funds',
        message: 'Something went wrong while loading your funds.',
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

/// Superuser entry into the operational shells. An admin isn't scoped to a
/// company, so these push the incharge / approval homes where an
/// [CompanyContextBar] lets them pick which company to operate in. Two
/// tappable rows, same card/tile rhythm as Users, so the landing stays scannable.
class _OperationsSection extends StatelessWidget {
  const _OperationsSection({
    required this.onOperateIncharge,
    required this.onOpenApprovals,
  });

  final VoidCallback onOperateIncharge;
  final VoidCallback onOpenApprovals;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Operations'),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.sm,
            vertical: AppTokens.xs,
          ),
          child: Column(
            children: [
              AppListTile(
                onTap: onOperateIncharge,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: AppTokens.brField,
                  ),
                  child: Icon(
                    Icons.point_of_sale_rounded,
                    color: scheme.onPrimaryContainer,
                    semanticLabel: 'Operate as incharge',
                  ),
                ),
                title: 'Operate as incharge',
                subtitle: 'Create requests, release cash, replenish',
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
              const Divider(
                height: 1,
                indent: AppTokens.md,
                endIndent: AppTokens.md,
              ),
              AppListTile(
                onTap: onOpenApprovals,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: AppTokens.brField,
                  ),
                  child: Icon(
                    Icons.fact_check_rounded,
                    color: scheme.onSecondaryContainer,
                    semanticLabel: 'Approvals inbox',
                  ),
                ),
                title: 'Approvals inbox',
                subtitle: 'Acknowledge or reject pending requests',
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.04, end: 0);
  }
}

/// Entry point to user maintenance (`/admin/users`). Fulfils the hero's promise
/// of managing "companies, funds, and users". A single tappable row keeps the
/// admin landing scannable; the heavy list lives on its own screen.
class _UsersSection extends StatelessWidget {
  const _UsersSection({required this.onManage});
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Users'),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.sm,
            vertical: AppTokens.xs,
          ),
          child: AppListTile(
            onTap: onManage,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: AppTokens.brField,
              ),
              child: Icon(
                Icons.group_rounded,
                color: scheme.onPrimaryContainer,
                semanticLabel: 'Users',
              ),
            ),
            title: 'Manage users',
            subtitle: 'Assign roles and companies',
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.04, end: 0);
  }
}

/// System-level configuration entry points. Currently the Cloudinary media
/// settings (`/admin/cloudinary`); same card/tile rhythm as Users.
class _SystemSection extends StatelessWidget {
  const _SystemSection({required this.onConfigureCloudinary});
  final VoidCallback onConfigureCloudinary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'System'),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.sm,
            vertical: AppTokens.xs,
          ),
          child: AppListTile(
            onTap: onConfigureCloudinary,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: AppTokens.brField,
              ),
              child: Icon(
                Icons.cloud_upload_rounded,
                color: scheme.onTertiaryContainer,
                semanticLabel: 'Cloudinary',
              ),
            ),
            title: 'Cloudinary',
            subtitle: 'Configure media uploads (cloud name, presets, folders)',
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.04, end: 0);
  }
}

/// Bold gradient banner anchoring the admin console with a one-line purpose.
class _AdminHero extends StatelessWidget {
  const _AdminHero();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.xl),
      decoration: BoxDecoration(
        gradient: AppTokens.heroGradient(scheme.primary),
        borderRadius: AppTokens.brCard,
        boxShadow: AppTokens.softShadow(scheme.primary),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.admin_panel_settings_rounded,
            color: Colors.white,
            size: 36,
            semanticLabel: 'Admin console',
          ),
          const SizedBox(width: AppTokens.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin console',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppTokens.xs),
                Text(
                  'Provision companies, funds, and users.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
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

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.md,
        vertical: AppTokens.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppTokens.rPill),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AdminSkeleton extends StatelessWidget {
  const _AdminSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppTokens.lg),
      children: [
        Skeleton.box(height: 96, radius: AppTokens.rCard),
        const SizedBox(height: AppTokens.xl),
        Skeleton.line(width: 140),
        const SizedBox(height: AppTokens.lg),
        const SurfaceCard(child: SkeletonList(count: 4)),
      ],
    );
  }
}

class _AdminError extends StatelessWidget {
  const _AdminError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: 'Something went wrong',
      message: message,
      showMascot: false,
    );
  }
}
