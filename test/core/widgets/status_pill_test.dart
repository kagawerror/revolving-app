import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/widgets/status_pill.dart';

void main() {
  // Plain default theme to avoid google-fonts network/font loading in tests.
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF0B6E4F));
  final darkScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0B6E4F),
    brightness: Brightness.dark,
  );

  group('StatusPill widget', () {
    testWidgets('renders its label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusPill(label: 'Released', tone: StatusTone.success),
          ),
        ),
      );

      expect(find.text('Released'), findsOneWidget);
    });

    testWidgets('renders an icon when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusPill(
              label: 'Rejected',
              tone: StatusTone.danger,
              icon: Icons.close_rounded,
            ),
          ),
        ),
      );

      expect(find.text('Rejected'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });
  });

  group('StatusPill.colorsFor', () {
    test('returns distinct backgrounds for success, danger and neutral', () {
      final success = StatusPill.colorsFor(StatusTone.success, scheme).$1;
      final danger = StatusPill.colorsFor(StatusTone.danger, scheme).$1;
      final neutral = StatusPill.colorsFor(StatusTone.neutral, scheme).$1;

      expect(success, isNot(equals(danger)));
      expect(success, isNot(equals(neutral)));
      expect(danger, isNot(equals(neutral)));
    });

    test('maps roles to the expected scheme colors', () {
      expect(
        StatusPill.colorsFor(StatusTone.success, scheme),
        equals((scheme.tertiaryContainer, scheme.onTertiaryContainer)),
      );
      expect(
        StatusPill.colorsFor(StatusTone.danger, scheme),
        equals((scheme.errorContainer, scheme.onErrorContainer)),
      );
      expect(
        StatusPill.colorsFor(StatusTone.info, scheme),
        equals((scheme.primaryContainer, scheme.onPrimaryContainer)),
      );
    });

    test('warning tone is brightness-aware (distinct light vs dark pairs)', () {
      final light = StatusPill.colorsFor(StatusTone.warning, scheme);
      final dark = StatusPill.colorsFor(StatusTone.warning, darkScheme);

      // Both pairs are defined and differ, so the dark pill tones down instead
      // of glowing as a bright island on dark surfaces.
      expect(light, isNot(equals(dark)));
      // Light pair: bright container, deep foreground. Dark pair inverts that.
      expect(light.$1.computeLuminance(), greaterThan(light.$2.computeLuminance()));
      expect(dark.$1.computeLuminance(), lessThan(dark.$2.computeLuminance()));
    });
  });
}
