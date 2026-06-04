import 'package:flutter/material.dart' show ThemeMode;

import '../../../core/error/result.dart';
import 'app_user.dart';

abstract interface class AuthRepository {
  /// Emits the current signed-in profile, or null when signed out.
  Stream<AppUser?> watchCurrentUser();

  Future<Result<AppUser>> signIn({required String email, required String password});

  Future<void> signOut();

  /// True when the app has not been bootstrapped yet (no `/meta/bootstrap`
  /// marker exists). Readable while signed out so the login screen can offer
  /// first-time setup.
  Future<Result<bool>> needsBootstrap();

  /// Creates the very first administrator account and marks the app as
  /// bootstrapped, atomically. Fails closed if setup was already completed.
  Future<Result<AppUser>> bootstrapFirstAdmin({
    required String email,
    required String password,
    required String displayName,
  });

  /// Merge-writes the caller's own self-service profile fields. Only non-null
  /// arguments are persisted; passing nothing is a successful no-op. Never
  /// touches admin-controlled fields (role/companyId).
  Future<Result<void>> updateProfile({
    String? displayName,
    String? photoUrl,
    ThemeMode? themeMode,
    String? accentId,
  });
}
