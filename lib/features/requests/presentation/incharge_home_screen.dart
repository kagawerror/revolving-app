import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure_ui.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/fund.dart';
import '../../companies/presentation/admin_providers.dart';
import '../../notifications/presentation/alerts_screen.dart';
import '../../notifications/presentation/low_balance_banner.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../replenishment/presentation/replenish_review_screen.dart';
import '../../replenishment/presentation/replenishment_providers.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'request_providers.dart';

/// Requests under a single fund.
final _fundRequestsProvider = StreamProvider.family((ref, String fundId) =>
    ref.watch(requestRepositoryProvider).watchByFund(fundId));

/// Compiles a replenishment draft for [fundId], then opens the review screen.
Future<void> _startReplenish(
    BuildContext context, WidgetRef ref, String fundId, String uid) async {
  final repo = ref.read(replenishmentRepositoryProvider);
  final res = await repo.createDraft(fundId: fundId, createdByUid: uid);
  if (!context.mounted) return;
  final id = res.valueOrNull;
  if (id == null) {
    context.showFailure(res.failureOrNull!);
    return;
  }
  // Read the freshly-created draft once.
  final draftList = await repo.watchByFund(fundId).first;
  final draft = draftList.firstWhere((r) => r.id == id);
  if (!context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReplenishReviewScreen(draft: draft)));
}

class InchargeHomeScreen extends ConsumerWidget {
  const InchargeHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Incharge'), actions: [
        const _AlertsBell(),
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
          : ref.watch(companyFundsProvider(user.companyId)).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (funds) => Column(
                  children: [
                    LowBalanceBanner(funds: funds),
                    Expanded(
                      child: funds.isEmpty
                          ? const Center(child: Text('No funds yet'))
                          : ListView(
                              children: [
                                for (final f in funds)
                                  _FundSection(fund: f),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
    );
  }
}

class _AlertsBell extends ConsumerWidget {
  const _AlertsBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadCountProvider);
    final icon = count > 0
        ? Badge(label: Text('$count'), child: const Icon(Icons.notifications))
        : const Icon(Icons.notifications);
    return IconButton(
      icon: icon,
      onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AlertsScreen())),
    );
  }
}

class _FundSection extends ConsumerWidget {
  final Fund fund;
  const _FundSection({required this.fund});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(_fundRequestsProvider(fund.id));
    final user = ref.read(currentUserProvider).valueOrNull;
    final canReplenish = (user?.role.canManageFund ?? false) &&
        fund.status != FundStatus.replenishing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(fund.name,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (canReplenish)
                TextButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Replenish'),
                  onPressed: () =>
                      _startReplenish(context, ref, fund.id, user!.uid),
                ),
            ],
          ),
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
    // Defense-in-depth: only an incharge custodian may release/ready requests
    // (mirrors the isIncharge() Firestore rule). Otherwise show status text.
    final canManage = user?.role.canManageFund ?? false;
    if (!canManage) return Text(request.status.name);
    switch (request.status) {
      case RequestStatus.acknowledged:
        return TextButton(
          onPressed: () async {
            final res = await repo.transition(
              request: request,
              to: RequestStatus.readyForRelease,
              actorUid: user!.uid,
            );
            if (context.mounted) res.showOnError(context);
          },
          child: const Text('Mark ready'),
        );
      case RequestStatus.readyForRelease:
        return FilledButton(
          onPressed: () async {
            final res =
                await repo.release(request: request, actorUid: user!.uid);
            if (context.mounted) res.showOnError(context);
          },
          child: const Text('Release'),
        );
      default:
        return Text(request.status.name);
    }
  }
}
