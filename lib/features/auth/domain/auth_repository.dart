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

  /// Changes the signed-in user's own password (the forced-rotation gate). Re-
  /// authenticates with [currentPassword], sets [newPassword], then clears the
  /// caller's `mustChangePassword` flag. Validates min-length / reuse before
  /// touching Auth. Returns a user-safe [Failure] on any step. Passwords are
  /// transient and never logged.
  Future<Result<void>> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Sends Firebase Auth's built-in password-reset email to [email] (the user
  /// receives a secure link to set a new password). Admin-initiated. The email
  /// address is PII and is never logged. Returns a user-safe [Failure] on error.
  Future<Result<void>> sendPasswordResetEmail({required String email});
}
