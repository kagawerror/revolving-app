import 'package:flutter/material.dart';

import '../features/auth/domain/app_user.dart';

/// The logical tabs a role shell can expose. The shell maps each tab to a body
/// widget (per role for [ShellTab.home]); this config stays body-free so it is
/// pure and trivially unit-testable.
enum ShellTab { home, acknowledged, dashboard, profile }

/// The primary create action for a shell. Shown ONLY on the Home tab and pushed
/// via GoRouter. Kept as a tiny value object so [ShellDestination] (and thus the
/// whole role config) is `const` and comparable.
@immutable
class ShellFab {
  final IconData icon;
  final String label;
  final String pushRoute;

  const ShellFab({
    required this.icon,
    required this.label,
    required this.pushRoute,
  });
}

/// One bottom-navigation destination. Carries everything the shell chrome needs
/// to render a tab EXCEPT the body widget: the body differs per role for
/// [ShellTab.home], so the shell owns the `ShellTab -> Widget` mapping and this
/// config stays role-agnostic and deterministic.
///
/// Design note — why no body here: keeping bodies out makes
/// [destinationsForRole] a pure function of `(role, showAcknowledged)`, so it
/// can be golden-tested without pumping widgets, and the same `home` body can be
/// swapped per role by the shell without forking the config.
@immutable
class ShellDestination {
  final ShellTab tab;

  /// Unselected (outlined) and selected (filled/rounded) icons. Material 3
  /// renders the selected icon inside the pill indicator.
  final IconData icon;
  final IconData selectedIcon;

  /// Short label shown under the destination in the [NavigationBar].
  final String label;

  /// AppBar title for this tab.
  final String title;

  /// The Home-only create action. Null on every non-Home tab.
  final ShellFab? fab;

  const ShellDestination({
    required this.tab,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.title,
    this.fab,
  });
}

// --- Shared tab definitions ------------------------------------------------
//
// Acknowledged / Dashboard / Profile are identical across roles, so they live
// as `const` singletons and are reused. Only the Home destination (title + fab)
// varies per role.

const _ackDestination = ShellDestination(
  tab: ShellTab.acknowledged,
  icon: Icons.checklist_outlined,
  selectedIcon: Icons.checklist_rounded,
  // Shortened from "Acknowledged" so the incharge's 4-tab bar never crowds /
  // truncates. "Worklist" is the term the screen already uses
  // (acknowledged_worklist_screen) and reads as an actionable queue.
  label: 'Worklist',
  title: 'Acknowledged',
);

const _dashboardDestination = ShellDestination(
  tab: ShellTab.dashboard,
  icon: Icons.dashboard_outlined,
  selectedIcon: Icons.dashboard_rounded,
  label: 'Dashboard',
  title: 'Dashboard',
);

const _profileDestination = ShellDestination(
  tab: ShellTab.profile,
  icon: Icons.person_outline,
  selectedIcon: Icons.person_rounded,
  label: 'Profile',
  title: 'Profile',
);

const _adminHome = ShellDestination(
  tab: ShellTab.home,
  icon: Icons.home_outlined,
  selectedIcon: Icons.home_rounded,
  label: 'Home',
  title: 'Admin',
  fab: ShellFab(
    icon: Icons.add,
    label: 'New fund',
    pushRoute: '/admin/create-fund',
  ),
);

const _inchargeHome = ShellDestination(
  tab: ShellTab.home,
  icon: Icons.home_outlined,
  selectedIcon: Icons.home_rounded,
  label: 'Home',
  title: 'Incharge',
  fab: ShellFab(
    icon: Icons.add,
    label: 'New request',
    pushRoute: '/incharge/create',
  ),
);

const _approverHome = ShellDestination(
  tab: ShellTab.home,
  icon: Icons.home_outlined,
  selectedIcon: Icons.home_rounded,
  label: 'Home',
  title: 'Approvals',
  // Approvers don't create funds/requests — no Home FAB.
);

/// Pure, deterministic destination list for a role's bottom-nav shell.
///
///   * **admin**    => Home, Dashboard, Profile
///   * **incharge** => Home, Worklist (acknowledged), Dashboard, Profile
///   * **approver** => Home, Dashboard, Profile
///   * **employee** (shares the incharge shell) => Home, Dashboard, Profile
///     (no Worklist — gate via [showAcknowledged]).
///
/// [showAcknowledged] is the single switch for the acknowledged tab; the shell
/// passes `role.canManageFundOrAdmin` for the incharge shell and `false`
/// elsewhere, so this function never needs to know about session state.
List<ShellDestination> destinationsForRole(
  UserRole role, {
  required bool showAcknowledged,
}) {
  if (role.isAdmin) {
    return const [_adminHome, _dashboardDestination, _profileDestination];
  }
  if (role.canApprove) {
    return const [_approverHome, _dashboardDestination, _profileDestination];
  }
  // incharge + employee share the incharge home/shell. Only fund-managers
  // (incharge, or an admin operating the shell) get the acknowledged worklist.
  return [
    _inchargeHome,
    if (showAcknowledged) _ackDestination,
    _dashboardDestination,
    _profileDestination,
  ];
}
