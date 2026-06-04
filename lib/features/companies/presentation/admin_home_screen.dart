import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/profile_avatar_button.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../messaging/presentation/messaging_providers.dart';
import 'admin_providers.dart';

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(companiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Admin'), actions: [
        IconButton(
          icon: const Icon(Icons.dashboard_outlined),
          tooltip: 'Dashboard',
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DashboardScreen())),
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => ref.read(signOutProvider)(),
        ),
        const ProfileAvatarButton(),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/create-fund'),
        label: const Text('New fund'),
        icon: const Icon(Icons.add),
      ),
      body: companies.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => ListView(
          children: [
            for (final c in list)
              ListTile(leading: const Icon(Icons.business), title: Text(c.name)),
          ],
        ),
      ),
    );
  }
}
