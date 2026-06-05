import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_tokens.dart';
import '../features/auth/domain/app_user.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/companies/presentation/admin_company_context_bar.dart';
import '../features/notifications/presentation/alerts_bell.dart';
import 'role_destinations.dart';

// Per-tab body widgets, one per ShellTab (Home is resolved per role below).
import '../features/companies/presentation/admin_home_body.dart';
import '../features/dashboard/presentation/dashboard_body.dart';
import '../features/profile/presentation/profile_body.dart';
import '../features/requests/presentation/acknowledged_worklist_body.dart';
import '../features/requests/presentation/admin_aging_body.dart';
import '../features/requests/presentation/aging_body.dart';
import '../features/requests/presentation/approver_approved_body.dart';
import '../features/requests/presentation/approver_home_body.dart';
import '../features/requests/presentation/incharge_home_body.dart';

/// Shared bottom-navigation shell for the three role landing screens.
///
/// Replaces the old top-app-bar "menu" (Dashboard / Profile / Acknowledged
/// icons) with a Material 3 [NavigationBar]. The top bar is reduced to a
/// per-tab title plus the [AlertsBell].
///
/// One widget serves all roles: it reads [destinationsForRole] for the tab set
/// and maps each [ShellTab] to a body. The Home body is role-specific
/// (admin / incharge / approver), so the mapping lives here rather than in the
/// pure config.
///
/// Bodies are kept alive across tab switches via [IndexedStack] so a scrolled
/// fund list or dashboard doesn't reset when the custodian flips to Profile and
/// back — important when releasing cash mid-review.
class RoleShellScreen extends ConsumerStatefulWidget {
  const RoleShellScreen({super.key, required this.role});

  /// The landing role for this shell. Drives the tab set, the Home body, and
  /// whether the acknowledged worklist appears.
  final UserRole role;

  @override
  ConsumerState<RoleShellScreen> createState() => _RoleShellScreenState();
}

class _RoleShellScreenState extends ConsumerState<RoleShellScreen> {
  int _index = 0;

  /// Maps a tab to its body. Home is resolved per role; the rest are shared.
  Widget _bodyFor(ShellTab tab) {
    switch (tab) {
      case ShellTab.home:
        if (widget.role.isAdmin) return const AdminHomeBody();
        if (widget.role.canApprove) return const ApproverHomeBody();
        return const InchargeHomeBody();
      case ShellTab.approved:
        return const ApproverApprovedBody();
      case ShellTab.acknowledged:
        return const AcknowledgedWorklistBody();
      case ShellTab.aging:
        return widget.role.isAdmin
            ? const AdminAgingBody()
            : const AgingBody();
      case ShellTab.dashboard:
        return const DashboardBody();
      case ShellTab.profile:
        return const ProfileBody();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The acknowledged worklist is fund-management only: incharge, or an admin
    // operating the incharge shell. The admin shell and approver shell never
    // show it. Reading currentUser keeps this honest even though the route's
    // role is fixed — an admin landing here would still resolve correctly.
    final me = ref.watch(currentUserProvider).valueOrNull;
    final showAcknowledged = !widget.role.isAdmin &&
        !widget.role.canApprove &&
        (me?.role.canManageFundOrAdmin ?? widget.role.canManageFundOrAdmin);

    // Aging on the incharge shell is incharge-only: an employee shares this
    // shell but must not see it. Gate on the real user's canManageFund (incharge
    // only) exactly like the worklist, reading currentUser so the route's fixed
    // role can't leak Aging to an employee. The admin shell lists Aging itself.
    final showAging = !widget.role.isAdmin &&
        !widget.role.canApprove &&
        (me?.role.canManageFund ?? widget.role.canManageFund);

    final destinations = destinationsForRole(
      widget.role,
      showAcknowledged: showAcknowledged,
      showAging: showAging,
    );

    // Guard against the tab set shrinking under a stale index (e.g. an admin's
    // role/membership resolving after first paint and dropping Worklist).
    final safeIndex = _index.clamp(0, destinations.length - 1);
    if (safeIndex != _index) {
      // Defer the state correction out of build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _index != safeIndex) setState(() => _index = safeIndex);
      });
    }
    final current = destinations[safeIndex];

    // The company-context picker belongs to the incharge / approver workflows
    // only, and only on the Home / Worklist surfaces (Dashboard and Profile are
    // not company-scoped here). Never on the admin shell.
    final showContextBar = !widget.role.isAdmin &&
        (current.tab == ShellTab.home ||
            current.tab == ShellTab.acknowledged);

    final fab = current.fab;

    return Scaffold(
      appBar: AppBar(
        title: Text(current.title),
        // Subtle separation from scrolling content: the app is flat
        // (elevation 0) but with a bottom nav we let the top bar tint a hair
        // when content scrolls under it, so the title never floats over text.
        scrolledUnderElevation: 0.5,
        actions: const [
          AlertsBell(),
          SizedBox(width: AppTokens.xs),
        ],
      ),
      body: Column(
        children: [
          if (showContextBar) const CompanyContextBar(),
          Expanded(
            child: IndexedStack(
              index: safeIndex,
              children: [
                for (final d in destinations) _bodyFor(d.tab),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: fab == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(fab.pushRoute),
              icon: Icon(fab.icon),
              label: Text(fab.label),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
              // Tooltip + label give the destination an explicit semantic name
              // for screen readers; the full word stays available even when the
              // visible label is shortened ("Worklist").
              tooltip: d.title,
            ),
        ],
      ),
    );
  }
}
