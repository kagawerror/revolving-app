import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'request_providers.dart';

final pendingRequestsProvider = StreamProvider<List<FundRequest>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref
      .watch(requestRepositoryProvider)
      .watchByStatus(user.companyId, RequestStatus.pendingAck);
});
