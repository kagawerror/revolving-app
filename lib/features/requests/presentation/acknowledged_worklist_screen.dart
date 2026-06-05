import 'package:flutter/material.dart';

import '../../companies/presentation/admin_company_context_bar.dart';
import 'acknowledged_worklist_body.dart';

/// Standalone deep-link route (`/incharge/acknowledged`) for the incharge
/// custodian's release worklist. Wraps [AcknowledgedWorklistBody] in its own
/// Scaffold + AppBar + [CompanyContextBar]; the same body also serves the
/// Worklist tab inside [RoleShellScreen].
class AcknowledgedWorklistScreen extends StatelessWidget {
  const AcknowledgedWorklistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acknowledged Requests')),
      body: const Column(
        children: [
          // Admin-only operating-company picker; renders nothing for non-admins,
          // so their layout is unchanged. The provider keys off the same
          // effective company this bar drives.
          CompanyContextBar(),
          Expanded(child: AcknowledgedWorklistBody()),
        ],
      ),
    );
  }
}
