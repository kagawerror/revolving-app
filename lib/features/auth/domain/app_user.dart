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

  const AppUser({
    required this.uid,
    required this.companyId,
    required this.role,
    required this.displayName,
    required this.email,
    this.companyIds = const [],
    this.photoUrl,
    this.themeMode = ThemeMode.system,
    this.accentId = 'forest',
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) => AppUser(
        uid: uid,
        companyId: (map['companyId'] ?? '') as String,
        companyIds: (map['companyIds'] as List?)?.cast<String>() ?? const [],
        role: UserRole.fromName(map['role'] as String?),
        displayName: (map['displayName'] ?? '') as String,
        email: (map['email'] ?? '') as String,
        photoUrl: map['photoUrl'] as String?,
        themeMode: _parseThemeMode(map['themeMode']),
        accentId: (map['accentId'] ?? 'forest') as String,
      );

  /// The companies this user may operate in, resolved with backward-compat:
  ///   * **admin** => `const []` (admins are superusers, not tied to a company).
  ///   * **non-admin with [companyIds]** => that list.
  ///   * **non-admin legacy doc** (empty [companyIds]) => `[companyId]`.
  List<String> get companyMemberships => role.isAdmin
      ? const []
      : (companyIds.isEmpty ? [companyId] : companyIds);

  /// Serializes the self-service profile fields. `themeMode` is stored as a
  /// stable string so the doc stays human-readable and migration-free.
  Map<String, dynamic> toMap() => {
        'companyId': companyId,
        // Admin-controlled membership only: this is NOT the self-service write
        // path (self-service writes a scoped field map in
        // firebase_auth_repository.dart), so companyIds is never user-mutable.
        'companyIds': companyIds,
        'role': role.name,
        'displayName': displayName,
        'email': email,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'themeMode': themeModeName(themeMode),
        'accentId': accentId,
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
        role,
        displayName,
        email,
        photoUrl,
        themeMode,
        accentId,
      ];
}
