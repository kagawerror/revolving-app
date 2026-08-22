import 'package:flutter/material.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../auth/domain/auth_repository.dart';

class ProfileController {
  ProfileController(this._repo);
  final AuthRepository _repo;

  Future<Result<void>> setAccent(String accentId) =>
      _repo.updateProfile(accentId: accentId);

  Future<Result<void>> setThemeMode(ThemeMode mode) =>
      _repo.updateProfile(themeMode: mode);

  Future<Result<void>> saveDisplayName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return Future.value(const Err(ValidationFailure('Name cannot be empty')));
    }
    return _repo.updateProfile(displayName: trimmed);
  }

  Future<Result<void>> savePhotoUrl(String url) =>
      _repo.updateProfile(photoUrl: url);
}
