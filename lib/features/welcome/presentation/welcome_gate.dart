import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'welcome_screen.dart';

/// How long the welcome fades out over when dismissed.
const Duration _kWelcomeFadeOut = Duration(milliseconds: 400);

/// Whether the welcome screen has been dismissed for this app session.
/// In-memory only → resets on every cold start, so the welcome shows on
/// every launch (by product decision). Not persisted.
final welcomeDismissedProvider = StateProvider<bool>((ref) => false);

/// Overlays [WelcomeScreen] on top of [child] (the routed app) until the
/// user taps "Let's Go".
///
/// The gate deliberately keeps [child] mounted *beneath* the welcome so the
/// real app builds and initializes (auth, messaging, routing) while the
/// greeting is on screen. On dismissal the welcome fades out and [child]
/// is revealed.
///
/// Dismissal state lives in [welcomeDismissedProvider] (in-memory), so the
/// welcome reappears on every cold start. There is intentionally no GoRouter
/// route for this — a router redirect would bounce it to /login or home.
/// The welcome never self-dismisses: it stays until the user acts.
class WelcomeGate extends ConsumerWidget {
  const WelcomeGate({super.key, required this.child});

  /// The routed app that sits beneath the welcome and is revealed on dismiss.
  final Widget child;

  /// Flips the session flag so the welcome fades out. Guards against firing
  /// after an earlier dismissal (no-op when already dismissed).
  void _dismiss(WidgetRef ref) {
    final notifier = ref.read(welcomeDismissedProvider.notifier);
    if (notifier.state) return;
    notifier.state = true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(welcomeDismissedProvider);

    return Stack(
      children: [
        // The routed app builds/initializes beneath the welcome.
        child,
        // Fades out (and is removed) once dismissed.
        AnimatedSwitcher(
          duration: _kWelcomeFadeOut,
          child: dismissed
              ? const SizedBox.shrink()
              : WelcomeScreen(onContinue: () => _dismiss(ref)),
        ),
      ],
    );
  }
}
