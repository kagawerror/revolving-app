import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rev_app/core/theme/app_theme.dart';

/// google_fonts builds the text theme by loading a font. In tests there is no
/// network and no bundled Plus Jakarta Sans, so we make google_fonts resolve the
/// font from the *asset bundle* (which skips its network checksum): we publish a
/// fake AssetManifest listing a Plus Jakarta Sans asset for every weight the
/// theme requests, and serve real TTF bytes for any font asset load. With
/// `allowRuntimeFetching = false`, google_fonts never touches the network.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;

    final Uint8List fontBytes =
        File('test/fixtures/Roboto-Regular.ttf').readAsBytesSync();

    // Asset keys google_fonts will accept for Plus Jakarta Sans. The matcher
    // only checks that the asset (minus extension) ends with the variant's API
    // filename prefix, so one key per weight used by AppTypography covers it.
    const fontAssets = <String>[
      'fonts/PlusJakartaSans-Regular.ttf',
      'fonts/PlusJakartaSans-Medium.ttf',
      'fonts/PlusJakartaSans-SemiBold.ttf',
      'fonts/PlusJakartaSans-Bold.ttf',
      'fonts/PlusJakartaSans-ExtraBold.ttf',
    ];

    // AssetManifest.bin is a StandardMessageCodec-encoded map of
    // asset-key -> list of variant descriptors ({'asset': key}). google_fonts
    // only reads the keys via listAssets(), but the value shape must still
    // decode cleanly.
    final assetManifest = <String, Object>{
      for (final a in fontAssets)
        a: <Object>[
          <String, Object>{'asset': a},
        ],
    };
    final ByteData manifestBin =
        const StandardMessageCodec().encodeMessage(assetManifest)!;

    final ByteData fontData = ByteData.view(fontBytes.buffer);

    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final String key = utf8.decode(message!.buffer.asUint8List());
        if (key == 'AssetManifest.bin') return manifestBin;
        if (fontAssets.contains(key)) return fontData;
        return null;
      },
    );
  });

  tearDownAll(() {
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  const seed = Color(0xFF4F46E5);

  test('light() uses Material 3 and a light scheme from the given seed', () {
    final ThemeData t = AppTheme.light(seed);
    expect(t.useMaterial3, isTrue);
    expect(t.colorScheme.brightness, Brightness.light);
  });

  test('dark() uses Material 3 and a dark scheme from the given seed', () {
    final ThemeData t = AppTheme.dark(seed);
    expect(t.useMaterial3, isTrue);
    expect(t.colorScheme.brightness, Brightness.dark);
  });

  // Regression: the FilledButton theme must impose a comfortable *height* floor
  // without forcing an infinite *min-width*. Size.fromHeight(h) is
  // Size(double.infinity, h) — baking that into the global theme made every
  // un-overridden FilledButton demand infinite width, which crashes the moment
  // a button lands in a width-unbounded parent (a Row/Wrap without Expanded,
  // e.g. AppListTile's trailing slot).
  test('filledButton theme keeps a finite min-width and a 52 height floor', () {
    final ButtonStyle? style = AppTheme.light(seed).filledButtonTheme.style;
    final Size? min = style?.minimumSize?.resolve(<WidgetState>{});
    expect(min, isNotNull);
    expect(min!.width.isFinite, isTrue,
        reason: 'global theme must not force infinite button width');
    expect(min.height, 52);
  });

  testWidgets(
      'FilledButton in an unbounded-width parent lays out without crashing',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(seed),
        home: Scaffold(
          // A bare Row child receives unbounded width on the main axis — the
          // same constraint AppListTile hands its `trailing` widget.
          body: Row(
            children: [
              FilledButton(onPressed: () {}, child: const Text('Act')),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
