import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/firebase/firebase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/firestore_replenishment_repository.dart';
import '../domain/replenishment.dart';
import '../domain/replenishment_repository.dart';
import '../domain/replenishment_status.dart';

final replenishmentRepositoryProvider = Provider<ReplenishmentRepository>(
    (ref) => FirestoreReplenishmentRepository(ref.watch(firestoreProvider)));

final pendingReplenishmentsProvider = StreamProvider<List<Replenishment>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref.watch(replenishmentRepositoryProvider)
      .watchByCompanyAndStatus(user.companyId, ReplenishmentStatus.submitted.name);
});
