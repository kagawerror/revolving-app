import 'package:flutter/material.dart';

import '../../companies/presentation/admin_company_context_bar.dart';
import 'conflict_worklist_body.dart';

/// Standalone deep-link route (`/incharge/conflicts`) for the incharge
/// custodian's overdraft-resolution queue. Wraps [ConflictWorklistBody] in its
/// own Scaffold + AppBar + [CompanyContextBar], mirroring
/// [AcknowledgedWorklistScreen]. Role-gated to incharge/admin in the router.
class ConflictWorklistScreen extends StatelessWidget {
  const ConflictWorklistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conflicts')),
      body: const Column(
        children: [
          // Admin-only operating-company picker; renders nothing for non-admins.
          CompanyContextBar(),
          Expanded(child: ConflictWorklistBody()),
        ],
      ),
    );
  }
}
