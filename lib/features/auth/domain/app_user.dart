import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart' show ThemeMode;

enum UserRole {
  admin,
  ceo,
  manager,
  superior,
  incharge,
  employee;

  static UserRole fromName(String? name) => UserRole.values.firstWhere(
        (r) => r.name == name,
        orElse: () => UserRole.employee,
      );

  /// Any superior-level role may acknowledge a request (single-approver model).
  bool get canApprove =>
      this == UserRole.superior || this == UserRole.manager || this == UserRole.ceo;

  /// Only the incharge custodian creates/releases requests and replenishes.
  bool get canManageFund => this == UserRole.incharge;

  bool get isAdmin => this == UserRole.admin;

  /// Superuser-aware approval capability: any approver role OR an admin (who may
  /// operate the approval workflow in any company). Keeps [canApprove]
  /// role-pure for the Firestore-rule mirror; gate UI/actions on this.
  bool get canApproveOrAdmin => canApprove || isAdmin;

  /// Superuser-aware fund-management capability: the incharge custodian OR an
  /// admin operating a chosen company. Keeps [canManageFund] role-pure.
  bool get canManageFundOrAdmin => canManageFund || isAdmin;

  /// May view the Reports surface (released-request + replenishment summaries):
  /// an admin (any company), the CEO, or the incharge custodian. Approvers and
  /// employees do not get the reporting view. The Firestore-rule mirror admits
  /// the same set on the read paths the reports query.
  bool get canViewReports => isAdmin || this == UserRole.ceo || canManageFund;

  /// May adjust a fund's available balance (Fund Adjustment workflow): an admin
  /// (any company) or the CEO (cross-company, intentional). Gate the
  /// adjust-fund UI/action on this; the Firestore-rule mirror admits the same
  /// two roles (`isAdmin() || isCeo()`).
  bool get canAdjustFund => isAdmin || this == UserRole.ceo;
}

class AppUser extends Equatable {
  final String uid;
  final String companyId;

  /// Full company membership for non-admin users. The **primary** company is
  /// [companyId] (also the first element by convention). Empty for admins and
  /// for legacy (pre-migration) docs — see [companyMemberships] for the
  /// fallback that makes legacy docs behave as single-company members.
  final List<String> companyIds;
  final UserRole role;
  final String displayName;
  final String email;
  final String? photoUrl;
  final ThemeMode themeMode;
  final String accentId;

  /// When true, the user is gated to [ChangePasswordScreen] until they set a new
  /// password. Stamped on admin account creation and on any admin-initiated
  /// password set (reset action + inline edit-form reset); cleared by the user's
  /// own successful [AuthRepository.changeOwnPassword]. Defaults false for legacy
  /// docs that predate the field.
  final bool mustChangePassword;

  /// Fund document IDs an **incharge** custodian is scoped to. Admin-controlled
  /// (set in the user-management dialog), never on the self-service write path —
  /// same contract as [companyIds]. Funds may span multiple of the incharge's
  /// [companyMemberships]; assigning a fund also grants its company. Meaningful
  /// only for the incharge role; empty/absent for everyone else and for legacy
  /// docs that predate the field. With the strict empty-state rule, an empty
  /// list means "no funds assigned" (no fallback to all company funds).
  final List<String> assignedFundIds;

  const AppUser({
    required this.uid,
    required this.companyId,
    required this.role,
    required this.displayName,
    required this.email,
    this.companyIds = const [],
    this.assignedFundIds = const [],
    this.photoUrl,
    this.themeMode = ThemeMode.system,
    this.accentId = 'forest',
    this.mustChangePassword = false,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) => AppUser(
        uid: uid,
        companyId: (map['companyId'] ?? '') as String,
        companyIds: (map['companyIds'] as List?)?.cast<String>() ?? const [],
        assignedFundIds:
            (map['assignedFundIds'] as List?)?.cast<String>() ?? const [],
        role: UserRole.fromName(map['role'] as String?),
        displayName: (map['displayName'] ?? '') as String,
        email: (map['email'] ?? '') as String,
        photoUrl: map['photoUrl'] as String?,
        themeMode: _parseThemeMode(map['themeMode']),
        accentId: (map['accentId'] ?? 'forest') as String,
        mustChangePassword: (map['mustChangePassword'] ?? false) as bool,
      );

  /// The companies this user may operate in, resolved with backward-compat:
  ///   * **admin** => `const []` (admins are superusers, not tied to a company).
  ///   * **non-admin with [companyIds]** => that list.
  ///   * **non-admin legacy doc** (empty [companyIds]) => `[companyId]`.
  List<String> get companyMemberships => role.isAdmin
      ? const []
      : (companyIds.isEmpty ? [companyId] : companyIds);

  /// Fund IDs this user is scoped to for display/eligibility. Empty for every
  /// non-incharge role (they aren't fund-scoped) AND for an unassigned incharge
  /// (strict empty state — no fallback). `resolveVisibleFunds` uses the role to
  /// tell those two cases apart.
  List<String> get fundAssignments =>
      role.canManageFund ? assignedFundIds : const [];

  /// Serializes the self-service profile fields. `themeMode` is stored as a
  /// stable string so the doc stays human-readable and migration-free.
  Map<String, dynamic> toMap() => {
        'companyId': companyId,
        // Admin-controlled membership only: this is NOT the self-service write
        // path (self-service writes a scoped field map in
        // firebase_auth_repository.dart), so companyIds is never user-mutable.
        'companyIds': companyIds,
        // Admin-controlled, like companyIds — never written on the self-service
        // path (that path writes a scoped field map elsewhere).
        'assignedFundIds': assignedFundIds,
        'role': role.name,
        'displayName': displayName,
        'email': email,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'themeMode': themeModeName(themeMode),
        'accentId': accentId,
        'mustChangePassword': mustChangePassword,
      };

  /// Stable string token for a [ThemeMode]: 'light' | 'dark' | 'system'.
  static String themeModeName(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode _parseThemeMode(Object? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  @override
  List<Object?> get props => [
        uid,
        companyId,
        companyIds,
        assignedFundIds,
        role,
        displayName,
        email,
        photoUrl,
        themeMode,
        accentId,
        mustChangePassword,
      ];
}
