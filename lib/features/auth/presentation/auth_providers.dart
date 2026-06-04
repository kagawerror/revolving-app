import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/firebase/firebase_providers.dart';
import '../data/firebase_auth_repository.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(
    ref.watch(firebaseAuthProvider),
    ref.watch(firestoreProvider),
  );
});

/// Stream of the current profile (null when signed out). The router watches this.
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).watchCurrentUser();
});

/// Whether the app still needs first-time setup (no admin seeded yet).
///
/// Fails CLOSED: any error resolves to `false` so a flaky or already-seeded
/// system never offers the founding-admin setup entry by mistake.
final bootstrapNeededProvider = FutureProvider<bool>((ref) async {
  final result = await ref.watch(authRepositoryProvider).needsBootstrap();
  return result.when(ok: (needed) => needed, err: (_) => false);
});
