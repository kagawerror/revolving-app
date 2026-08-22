import 'package:flutter/material.dart';

import '../../companies/presentation/admin_company_context_bar.dart';
import 'post_release_review_body.dart';

/// Standalone deep-link route (`/approvals/review`) for the approver's
/// post-release review queue. Wraps [PostReleaseReviewBody] in its own
/// Scaffold + AppBar + [CompanyContextBar], mirroring
/// [AcknowledgedWorklistScreen]. Role-gated to approvers/admin in the router.
class PostReleaseReviewScreen extends StatelessWidget {
  const PostReleaseReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('To review')),
      body: const Column(
        children: [
          // Admin-only operating-company picker; renders nothing for non-admins.
          CompanyContextBar(),
          Expanded(child: PostReleaseReviewBody()),
        ],
      ),
    );
  }
}
