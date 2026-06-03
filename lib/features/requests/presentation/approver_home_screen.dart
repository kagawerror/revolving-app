import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/presentation/dashboard_screen.dart';
import '../../messaging/presentation/messaging_providers.dart';
import '../../notifications/presentation/alerts_bell.dart';
import '../../replenishment/presentation/replenishment_detail_screen.dart';
import '../../replenishment/presentation/replenishment_providers.dart';
import 'approver_inbox_providers.dart';
import 'request_detail_screen.dart';

class ApproverHomeScreen extends ConsumerWidget {
  const ApproverHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingRequestsProvider);
    final replenishments = ref.watch(pendingReplenishmentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Approvals'), actions: [
        IconButton(
          icon: const Icon(Icons.dashboard_outlined),
          tooltip: 'Dashboard',
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DashboardScreen())),
        ),
        const AlertsBell(),
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => ref.read(signOutProvider)(),
        ),
      ]),
      body: ListView(children: [
        _SectionHeader('Pending replenishments'),
        replenishments.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Error: $e'),
          ),
          data: (list) => list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('No pending replenishments'),
                )
              : Column(children: [
                  for (final r in list)
                    ListTile(
                      title: Text('Replenishment — ${r.total.format()}'),
                      subtitle: Text('${r.itemCount} item(s)'),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              ReplenishmentDetailScreen(replenishment: r))),
                    ),
                ]),
        ),
        _SectionHeader('Pending requests'),
        pending.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Error: $e'),
          ),
          data: (list) => list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('No pending requests'),
                )
              : Column(children: [
                  for (final r in list)
                    ListTile(
                      title: Text('${r.beneficiaryName} — ${r.amount.format()}'),
                      subtitle: Text(r.purpose),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => RequestDetailScreen(request: r))),
                    ),
                ]),
        ),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
