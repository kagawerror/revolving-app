import 'package:flutter/material.dart';

/// Static design tokens shared across the app. Bold/vibrant: large radii,
/// soft shadows, accent-derived gradients.
class AppTokens {
  AppTokens._();

  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32;

  static const double rCard = 22, rField = 14, rPill = 999;
  static const BorderRadius brCard = BorderRadius.all(Radius.circular(rCard));
  static const BorderRadius brField = BorderRadius.all(Radius.circular(rField));

  static List<BoxShadow> softShadow(Color base) => [
        BoxShadow(
          color: base.withValues(alpha: 0.10),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  static LinearGradient heroGradient(Color seed) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [seed, Color.lerp(seed, Colors.black, 0.28)!],
      );
}
