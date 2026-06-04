import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'welcome_screen.dart';

/// How long the welcome screen stays up before it auto-dismisses itself.
const Duration kWelcomeAutoDismiss = Duration(seconds: 4);

/// How long the welcome fades out over when dismissed.
const Duration _kWelcomeFadeOut = Duration(milliseconds: 400);

/// Whether the welcome screen has been dismissed for this app session.
/// In-memory only → resets on every cold start, so the welcome shows on
/// every launch (by product decision). Not persisted.
final welcomeDismissedProvider = StateProvider<bool>((ref) => false);

/// Overlays [WelcomeScreen] on top of [child] (the routed app) until the
/// welcome is dismissed — either by the auto-dismiss timer or by the user
/// tapping "Get Started".
///
/// The gate deliberately keeps [child] mounted *beneath* the welcome so the
/// real app builds and initializes (auth, messaging, routing) while the
/// greeting is on screen. On dismissal the welcome fades out and [child]
/// is revealed.
///
/// Dismissal state lives in [welcomeDismissedProvider] (in-memory), so the
/// welcome reappears on every cold start. There is intentionally no GoRouter
/// route for this — a router redirect would bounce it to /login or home.
class WelcomeGate extends ConsumerStatefulWidget {
  const WelcomeGate({
    super.key,
    required this.child,
    this.autoDismissAfter = kWelcomeAutoDismiss,
  });

  /// The routed app that sits beneath the welcome and is revealed on dismiss.
  final Widget child;

  /// Delay before the welcome auto-dismisses itself. Tests pass a short
  /// duration; production uses [kWelcomeAutoDismiss].
  final Duration autoDismissAfter;

  @override
  ConsumerState<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends ConsumerState<WelcomeGate> {
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _autoDismissTimer = Timer(widget.autoDismissAfter, _dismiss);
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    super.dispose();
  }

  /// Flips the session flag so the welcome fades out. Guards against firing
  /// after disposal or after an earlier dismissal (button + timer race).
  void _dismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    if (!mounted) return;
    final notifier = ref.read(welcomeDismissedProvider.notifier);
    if (notifier.state) return;
    notifier.state = true;
  }

  @override
  Widget build(BuildContext context) {
    final dismissed = ref.watch(welcomeDismissedProvider);

    return Stack(
      children: [
        // The routed app builds/initializes beneath the welcome.
        widget.child,
        // Fades out (and is removed) once dismissed.
        AnimatedSwitcher(
          duration: _kWelcomeFadeOut,
          child: dismissed
              ? const SizedBox.shrink()
              : WelcomeScreen(onContinue: _dismiss),
        ),
      ],
    );
  }
}
