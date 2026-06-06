import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_prompt.dart';
import 'update_providers.dart';

/// Watches the one-shot update check and shows the update prompt once when a
/// newer version is available. Renders [child] unchanged otherwise — the check
/// never blocks the UI. Mirrors the MessagingInitializer/WelcomeGate wrapper
/// pattern in main.dart.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(updateCheckProvider, (_, next) {
      next.whenData((decision) {
        if (decision.hasUpdate && !_shown) {
          _shown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) showUpdatePrompt(context, decision.latest!);
          });
        }
      });
    });
    // Touch the provider so the lazy FutureProvider actually runs.
    ref.watch(updateCheckProvider);
    return widget.child;
  }
}
