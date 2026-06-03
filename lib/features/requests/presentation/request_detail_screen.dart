import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'request_providers.dart';

class RequestDetailScreen extends ConsumerWidget {
  final FundRequest request;
  const RequestDetailScreen({super.key, required this.request});

  Future<void> _decide(
      BuildContext context, WidgetRef ref, RequestStatus to) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final res = await ref.read(requestRepositoryProvider).transition(
          request: request,
          to: to,
          actorUid: user.uid,
        );
    if (!context.mounted) return;
    res.when(
      ok: (_) => Navigator.of(context).pop(),
      err: (f) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.message))),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canApprove =
        ref.watch(currentUserProvider).valueOrNull?.role.canApprove ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Request')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (request.hasProof)
          Image.network(request.proofImageUrl, height: 220),
        const SizedBox(height: 12),
        Text('Beneficiary: ${request.beneficiaryName}'),
        Text('Amount: ${request.amount.format()}'),
        Text('Purpose: ${request.purpose}'),
        Text('Status: ${request.status.name}'),
        const SizedBox(height: 24),
        if (canApprove && request.status == RequestStatus.pendingAck)
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: () =>
                    _decide(context, ref, RequestStatus.acknowledged),
                child: const Text('Approve'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _decide(context, ref, RequestStatus.rejected),
                child: const Text('Reject'),
              ),
            ),
          ]),
      ]),
    );
  }
}
