import 'package:flutter/material.dart';

/// First screen shown on every app launch.
///
/// Pure presentation: introduces the mascot ("Revvy") and what the app does,
/// then calls [onContinue] when the primary button is tapped. It does no
/// navigation, timing, or state — the parent gate owns dismissal.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onContinue});

  /// Fired when the user taps the primary "Get Started" button.
  final VoidCallback onContinue;

  static const String _mascotAsset = 'assets/images/revvy.jpg';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    // Soft vertical gradient derived entirely from the seeded scheme so it
    // tracks the brand colour without hardcoding hex values.
    final background = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        colorScheme.primaryContainer,
        Color.alphaBlend(
          colorScheme.primaryContainer.withValues(alpha: 0.35),
          colorScheme.surface,
        ),
        colorScheme.surface,
      ],
      stops: const [0.0, 0.45, 1.0],
    );

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: background),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Cap the mascot so it never dominates short / landscape screens.
              final mascotSize = (constraints.maxHeight * 0.34)
                  .clamp(140.0, 320.0)
                  .toDouble();

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        _AnimatedEntrance(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _MascotFrame(
                                asset: _mascotAsset,
                                size: mascotSize,
                                colorScheme: colorScheme,
                              ),
                              const SizedBox(height: 32),
                              _Greeting(
                                textTheme: textTheme,
                                colorScheme: colorScheme,
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(height: 24),
                        _ContinueButton(onContinue: onContinue),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Mascot framed in a softly-shadowed rounded card with a gentle glow so the
/// image's flat grey backdrop blends into the screen and looks intentional.
class _MascotFrame extends StatelessWidget {
  const _MascotFrame({
    required this.asset,
    required this.size,
    required this.colorScheme,
  });

  final String asset;
  final double size;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    const radius = 36.0;

    // Decode the image downsampled to the physical pixels it actually fills
    // (logical size × device pixel ratio) rather than its full native ~780×1170.
    // This cuts decode cost + memory on the startup-sensitive first frame.
    final cacheWidth =
        (size * MediaQuery.devicePixelRatioOf(context)).round();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surface,
            colorScheme.surfaceContainerHighest,
          ],
        ),
        boxShadow: [
          // Soft brand-tinted glow.
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.22),
            blurRadius: 48,
            spreadRadius: 4,
            offset: const Offset(0, 12),
          ),
          // Crisp ambient depth.
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 8),
          child: Image.asset(
            asset,
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            semanticLabel:
                'Revvy, the rev_app mascot: a friendly fox in a business '
                'suit holding a gold coin and a tablet showing a growth chart.',
          ),
        ),
      ),
    );
  }
}

/// Name greeting + one-line description of what the app does.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.textTheme, required this.colorScheme});

  final TextTheme textTheme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Hi, I’m Revvy \u{1F44B}',
          textAlign: TextAlign.center,
          style: textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your Revolving Fund',
          textAlign: TextAlign.center,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.primary,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            'Your friendly guide to managing your company’s revolving '
            'fund — track requests, approvals, and replenishments, '
            'all in one place.',
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-width primary action with a comfortable tap target (>= 48dp).
class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onContinue,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: const Text('Get Started'),
    );
  }
}

/// Self-contained fade + slight slide/scale-up entrance.
///
/// Uses [TweenAnimationBuilder] so there is no [AnimationController] to dispose
/// — it animates once on first build and is leak-free.
class _AnimatedEntrance extends StatelessWidget {
  const _AnimatedEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            // Rises ~24px as it fades in.
            offset: Offset(0, (1 - t) * 24),
            child: Transform.scale(
              // Subtle scale-up from 96% -> 100%.
              scale: 0.96 + (0.04 * t),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
