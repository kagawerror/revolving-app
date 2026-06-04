import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/firebase/firebase_providers.dart';
import '../../auth/domain/app_user.dart';
import '../data/firestore_user_admin_repository.dart';
import '../domain/user_admin_repository.dart';

final userAdminRepositoryProvider = Provider<UserAdminRepository>(
  (ref) => FirestoreUserAdminRepository(ref.watch(firestoreProvider)),
);

/// Every user profile, admin console list source. Three-state aware in the UI.
final allUsersProvider = StreamProvider<List<AppUser>>(
  (ref) => ref.watch(userAdminRepositoryProvider).watchAll(),
);
