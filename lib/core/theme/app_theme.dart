import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light(Color seed) =>
      _build(ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light));

  static ThemeData dark(Color seed) =>
      _build(ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark));

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: AppTypography.textTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: AppTokens.brCard),
        color: scheme.surfaceContainerLow,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Height-only floor for a comfortable tap target. Do NOT use
          // Size.fromHeight here: that is Size(double.infinity, h), which forces
          // an infinite *min-width* on every FilledButton app-wide and crashes
          // the moment one lands in a width-unbounded parent (a Row/Wrap without
          // Expanded — e.g. AppListTile's trailing slot). Buttons that want to
          // be full-width opt in explicitly via Size.fromHeight(52) or a
          // stretching parent (Column.stretch / ListView).
          minimumSize: const Size(64, 52),
          shape: const RoundedRectangleBorder(borderRadius: AppTokens.brField),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: const OutlineInputBorder(
          borderRadius: AppTokens.brField,
          borderSide: BorderSide.none,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
      ),
    );
  }
}
