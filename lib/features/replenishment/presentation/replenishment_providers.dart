import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/firebase/firebase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_active_company.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../../messaging/presentation/messaging_providers.dart';
import '../data/firestore_replenishment_repository.dart';
import '../domain/replenishment.dart';
import '../domain/replenishment_repository.dart';
import '../domain/replenishment_status.dart';

final replenishmentRepositoryProvider = Provider<ReplenishmentRepository>(
    (ref) => FirestoreReplenishmentRepository(
        ref.watch(firestoreProvider), ref.watch(pushSenderProvider)));

final pendingReplenishmentsProvider = StreamProvider<List<Replenishment>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  final companyId =
      effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));
  if (companyId.isEmpty) return const Stream.empty();
  return ref.watch(replenishmentRepositoryProvider)
      .watchByCompanyAndStatus(companyId, ReplenishmentStatus.submitted.name);
});

/// Admin-only: submitted replenishments across every company.
final allPendingReplenishmentsProvider = StreamProvider<List<Replenishment>>((ref) =>
    ref.watch(replenishmentRepositoryProvider)
        .watchByStatusAll(ReplenishmentStatus.submitted.name));
