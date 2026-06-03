import 'package:flutter/material.dart';

import '../../companies/domain/fund.dart';

class LowBalanceBanner extends StatelessWidget {
  final List<Fund> funds;
  const LowBalanceBanner({super.key, required this.funds});

  @override
  Widget build(BuildContext context) {
    final low = funds.where((f) => f.status == FundStatus.low).toList();
    if (low.isEmpty) return const SizedBox.shrink();
    return MaterialBanner(
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      content: Text('${low.length} fund(s) at low balance — replenish soon.'),
      actions: const [SizedBox.shrink()],
    );
  }
}
