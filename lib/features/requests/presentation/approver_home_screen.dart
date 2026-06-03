import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import 'approver_inbox_providers.dart';
import 'request_detail_screen.dart';

class ApproverHomeScreen extends ConsumerWidget {
  const ApproverHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Approvals'), actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
        ),
      ]),
      body: pending.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('No pending requests'))
            : ListView(children: [
                for (final r in list)
                  ListTile(
                    title: Text('${r.beneficiaryName} — ${r.amount.format()}'),
                    subtitle: Text(r.purpose),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => RequestDetailScreen(request: r))),
                  ),
              ]),
      ),
    );
  }
}
