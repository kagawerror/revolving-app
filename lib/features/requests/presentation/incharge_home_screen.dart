import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_providers.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'request_providers.dart';

/// Funds owned by the incharge's company.
final _companyFundsProvider = StreamProvider.family((ref, String companyId) =>
    ref.watch(fundRepositoryProvider).watchByCompany(companyId));

/// Requests under a single fund.
final _fundRequestsProvider = StreamProvider.family((ref, String fundId) =>
    ref.watch(requestRepositoryProvider).watchByFund(fundId));

class InchargeHomeScreen extends ConsumerWidget {
  const InchargeHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Incharge'), actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/incharge/create'),
        label: const Text('New request'),
        icon: const Icon(Icons.add),
      ),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : ref.watch(_companyFundsProvider(user.companyId)).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (funds) => funds.isEmpty
                    ? const Center(child: Text('No funds yet'))
                    : ListView(
                        children: [
                          for (final f in funds)
                            _FundSection(fundId: f.id, fundName: f.name),
                        ],
                      ),
              ),
    );
  }
}

class _FundSection extends ConsumerWidget {
  final String fundId;
  final String fundName;
  const _FundSection({required this.fundId, required this.fundName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(_fundRequestsProvider(fundId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(fundName,
              style: Theme.of(context).textTheme.titleMedium),
        ),
        requests.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Error: $e'),
          ),
          data: (list) => list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('No requests'),
                )
              : Column(
                  children: [
                    for (final r in list)
                      ListTile(
                        title: Text(
                            '${r.beneficiaryName} — ${r.amount.format()}'),
                        subtitle: Text(r.purpose),
                        trailing: _RequestAction(request: r),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _RequestAction extends ConsumerWidget {
  final FundRequest request;
  const _RequestAction({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(requestRepositoryProvider);
    final user = ref.read(currentUserProvider).valueOrNull;
    switch (request.status) {
      case RequestStatus.acknowledged:
        return TextButton(
          onPressed: user == null
              ? null
              : () async {
                  final res = await repo.transition(
                    request: request,
                    to: RequestStatus.readyForRelease,
                    actorUid: user.uid,
                  );
                  if (context.mounted && res.failureOrNull != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(res.failureOrNull!.message)));
                  }
                },
          child: const Text('Mark ready'),
        );
      case RequestStatus.readyForRelease:
        return FilledButton(
          onPressed: user == null
              ? null
              : () async {
                  final res = await repo.release(
                      request: request, actorUid: user.uid);
                  if (context.mounted && res.failureOrNull != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(res.failureOrNull!.message)));
                  }
                },
          child: const Text('Release'),
        );
      default:
        return Text(request.status.name);
    }
  }
}
