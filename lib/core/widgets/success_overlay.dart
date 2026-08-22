import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_tokens.dart';
import 'empty_state.dart';

/// A transient celebratory confirmation: Revvy plus a short message. Auto-
/// dismisses after ~1.6s, or on tap. Use after a successful money action
/// (release, replenish sign-off) to give honest, friendly feedback.
class SuccessOverlay extends StatefulWidget {
  const SuccessOverlay._({required this.message});

  final String message;

  /// Shows the overlay above the current route. Safe to await; the call returns
  /// once the dialog is dismissed.
  static Future<void> show(BuildContext context, String message) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) => SuccessOverlay._(message: message),
    );
  }

  @override
  State<SuccessOverlay> createState() => _SuccessOverlayState();
}

class _SuccessOverlayState extends State<SuccessOverlay> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1600), _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    _timer?.cancel();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppTokens.xl),
      child: GestureDetector(
        onTap: _dismiss,
        child: Container(
          padding: const EdgeInsets.all(AppTokens.xl),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: AppTokens.brCard,
            boxShadow: AppTokens.softShadow(scheme.shadow),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTokens.rCard),
                    child: Image.asset(
                      EmptyState.mascotAsset,
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                      semanticLabel: 'Revvy, the rev_app mascot',
                      errorBuilder: (context, error, stack) => Icon(
                        Icons.check_circle_rounded,
                        size: 96,
                        color: scheme.tertiary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(AppTokens.xs),
                    decoration: BoxDecoration(
                      color: scheme.tertiary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.surfaceContainerLow,
                        width: 3,
                      ),
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: scheme.onTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.lg),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 200.ms).scale(
            begin: const Offset(0.85, 0.85),
            end: const Offset(1, 1),
            duration: 260.ms,
            curve: Curves.easeOutBack,
          ),
    );
  }
}
