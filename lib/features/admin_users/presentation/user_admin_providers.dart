import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_secrets.dart';
import '../../../services/firebase/firebase_providers.dart';
import '../../auth/domain/app_user.dart';
import '../data/firestore_user_admin_repository.dart';
import '../data/http_admin_password_repository.dart';
import '../domain/admin_password_repository.dart';
import '../domain/user_admin_repository.dart';

final userAdminRepositoryProvider = Provider<UserAdminRepository>(
  (ref) => FirestoreUserAdminRepository(ref.watch(firestoreProvider)),
);

/// Admin "set/reset another user's password" capability, backed by the
/// admin-relay Worker. When [AppSecrets.adminRelayUrl] is blank the repository
/// short-circuits to a configured failure (and the UI hides the field).
final adminPasswordRepositoryProvider = Provider<AdminPasswordRepository>((ref) {
  return HttpAdminPasswordRepository(
    relayUrl: AppSecrets.adminRelayUrl,
    auth: ref.watch(firebaseAuthProvider),
  );
});

/// Every user profile, admin console list source. Three-state aware in the UI.
final allUsersProvider = StreamProvider<List<AppUser>>(
  (ref) => ref.watch(userAdminRepositoryProvider).watchAll(),
);
