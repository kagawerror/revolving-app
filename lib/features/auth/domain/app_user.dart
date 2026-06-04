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
}

class AppUser extends Equatable {
  final String uid;
  final String companyId;
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
    this.photoUrl,
    this.themeMode = ThemeMode.system,
    this.accentId = 'forest',
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) => AppUser(
        uid: uid,
        companyId: (map['companyId'] ?? '') as String,
        role: UserRole.fromName(map['role'] as String?),
        displayName: (map['displayName'] ?? '') as String,
        email: (map['email'] ?? '') as String,
        photoUrl: map['photoUrl'] as String?,
        themeMode: _parseThemeMode(map['themeMode']),
        accentId: (map['accentId'] ?? 'forest') as String,
      );

  /// Serializes the self-service profile fields. `themeMode` is stored as a
  /// stable string so the doc stays human-readable and migration-free.
  Map<String, dynamic> toMap() => {
        'companyId': companyId,
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
  List<Object?> get props =>
      [uid, companyId, role, displayName, email, photoUrl, themeMode, accentId];
}
