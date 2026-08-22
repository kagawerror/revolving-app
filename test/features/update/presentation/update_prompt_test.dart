import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ota_update/ota_update.dart';
import 'package:rev_app/features/update/domain/app_version_info.dart';
import 'package:rev_app/features/update/presentation/update_installer.dart';
import 'package:rev_app/features/update/presentation/update_prompt.dart';

/// Installer whose event stream is controlled by the test.
class _FakeInstaller extends UpdateInstaller {
  const _FakeInstaller(this.events);

  final List<OtaEvent> events;

  @override
  Stream<OtaEvent> downloadAndInstall(String apkUrl) =>
      Stream<OtaEvent>.fromIterable(events);
}

const _latest = AppVersionInfo(
  versionCode: 2,
  versionName: '1.2.0',
  apkUrl: 'https://example.com/rev_app-1.2.0+2.apk',
  notes: 'Bug fixes.',
);

Widget _harness(UpdateInstaller installer, {ValueChanged<int>? onSkipVersion}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showUpdatePrompt(context, _latest,
                installer: installer, onSkipVersion: onSkipVersion),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('error status event restores action buttons with an error',
      (tester) async {
    final installer = _FakeInstaller([OtaEvent(OtaStatus.DOWNLOAD_ERROR, '0')]);
    await tester.pumpWidget(_harness(installer));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(find.text('Update failed. Please try again later.'), findsOneWidget);
    // Buttons are back (not stuck on the progress bar).
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('Later does NOT persist a skip and pops the dialog',
      (tester) async {
    final skipped = <int>[];
    // No events: the user never starts the download.
    final installer = _FakeInstaller(const []);
    await tester.pumpWidget(
        _harness(installer, onSkipVersion: skipped.add));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Later'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    // The dialog closed...
    expect(find.text('Later'), findsNothing);
    // ...but the version was NOT skipped, so it can re-prompt next launch.
    expect(skipped, isEmpty);
  });

  testWidgets('install error DOES persist a skip (crash-loop safety valve)',
      (tester) async {
    final skipped = <int>[];
    final installer = _FakeInstaller([OtaEvent(OtaStatus.DOWNLOAD_ERROR, '0')]);
    await tester.pumpWidget(
        _harness(installer, onSkipVersion: skipped.add));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(find.text('Update failed. Please try again later.'), findsOneWidget);
    // The broken build is remembered so it can't loop forever.
    expect(skipped, [_latest.versionCode]);
  });

  testWidgets('downloading event shows progress', (tester) async {
    final installer = _FakeInstaller([OtaEvent(OtaStatus.DOWNLOADING, '50')]);
    await tester.pumpWidget(_harness(installer));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Downloading… 50%'), findsOneWidget);
  });
}
