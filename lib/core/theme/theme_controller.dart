import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/auth_providers.dart';
import 'app_accents.dart';

@immutable
class ThemeState {
  const ThemeState({required this.mode, required this.seed});

  final ThemeMode mode;
  final Color seed;

  @override
  bool operator ==(Object other) =>
      other is ThemeState && other.mode == mode && other.seed == seed;

  @override
  int get hashCode => Object.hash(mode, seed);
}

/// Pure reducer: AppUser (or null) -> ThemeState. Unit-tested.
ThemeState themeStateForUser(AppUser? user) {
  if (user == null) {
    return ThemeState(
      mode: ThemeMode.system,
      seed: AppAccents.byId(AppAccents.defaultId).seed,
    );
  }
  return ThemeState(
    mode: user.themeMode,
    seed: AppAccents.byId(user.accentId).seed,
  );
}

/// Drives MaterialApp. Re-derives from the auth stream; defaults while loading.
///
/// [ThemeState] overrides equality so an equal re-emission from the auth stream
/// does not rebuild [MaterialApp].
final themeControllerProvider = Provider<ThemeState>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  return themeStateForUser(user);
});
