import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/profile_avatar_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/surface_card.dart';
import '../../companies/domain/company.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../messaging/presentation/messaging_providers.dart';
import 'add_company_dialog.dart';
import 'admin_providers.dart';

/// Admin landing screen: provisioned companies + the entry point to create a
/// fund. Presentation-only redesign — the data source (`companiesProvider`),
/// sign-out action, dashboard navigation, profile entry, and create-fund route
/// are all preserved exactly.
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company added')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(companiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Admin'), actions: [
        IconButton(
          icon: const Icon(Icons.dashboard_outlined),
          tooltip: 'Dashboard',
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DashboardScreen())),
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Sign out',
          onPressed: () => ref.read(signOutProvider)(),
        ),
        const ProfileAvatarButton(),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/create-fund'),
        label: const Text('New fund'),
        icon: const Icon(Icons.add),
      ),
      body: companies.when(
        loading: () => const _AdminSkeleton(),
        error: (e, _) => _AdminError(message: 'Error: $e'),
        data: (list) => _AdminBody(
          companies: list,
          onAddCompany: () => _handleAddCompany(context, ref),
        ),
      ),
    );
  }
}

class _AdminBody extends StatelessWidget {
  const _AdminBody({required this.companies, required this.onAddCompany});

  final List<Company> companies;
  final VoidCallback onAddCompany;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppTokens.lg),
      children: [
        const _AdminHero(),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppTokens.md),
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
                    message: 'Add a company first, then create a fund for it. '
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
                        const Divider(height: 1, indent: AppTokens.md, endIndent: AppTokens.md),
                      _CompanyTile(company: companies[i]),
                    ],
                  ],
                ),
        ),
        // Bottom breathing room so the FAB never covers the last row.
        const SizedBox(height: 80),
      ],
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.04, end: 0);
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({required this.company});

  final Company company;

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
    );
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
