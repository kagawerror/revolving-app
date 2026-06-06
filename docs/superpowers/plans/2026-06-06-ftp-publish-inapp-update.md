# FTP Publish + In-App HTTPS Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish release APKs to an FTP server from the developer's machine and serve them over HTTPS, so the installed Android app detects a newer version on launch and lets the user download + install it in-app.

**Architecture:** Two isolated halves. (1) A gitignored publish script on the developer's Mac that builds the APK, writes a `version.json` manifest, and uploads both over FTP(S) — the only place FTP credentials ever live. (2) A new `lib/features/update/` Flutter feature (domain → data → presentation, the app's standard layering) that fetches the public manifest over HTTPS, compares version codes via a pure `decideUpdate` function, and shows a dismissible install prompt. The FTP password is never compiled into the app.

**Tech Stack:** Flutter, Dart, Riverpod, `http` (already a dep), `package_info_plus` (new), `ota_update` (new), `curl` (publish script), bash.

**Spec:** `docs/superpowers/specs/2026-06-06-ftp-publish-inapp-update-design.md`

**Platform scope:** Android only. iOS/web short-circuit to "up to date".

---

## File Structure

| File | Responsibility |
|---|---|
| `.gitignore` (modify) | Ignore `publish/.ftp.env` |
| `publish/.ftp.env.example` (create) | Committed template for FTP config |
| `publish/ftp_publish.sh` (create) | Build APK, write manifest, upload over FTP(S) |
| `lib/core/config/app_secrets.dart` (modify) | Add `updateManifestUrl` + `hasUpdates` |
| `.env.example` (modify) | Document `UPDATE_MANIFEST_URL` |
| `lib/features/update/domain/app_version_info.dart` (create) | Manifest model + `fromMap` |
| `lib/features/update/domain/update_decision.dart` (create) | Pure `decideUpdate` (testable seam) |
| `lib/features/update/data/update_repository.dart` (create) | `UpdateRepository` + `HttpUpdateRepository`, returns `Result` |
| `lib/features/update/presentation/update_providers.dart` (create) | Riverpod wiring + `updateCheckProvider` |
| `lib/features/update/presentation/update_installer.dart` (create) | `ota_update` download+install wrapper |
| `lib/features/update/presentation/update_prompt.dart` (create) | Dismissible confirmation dialog + progress |
| `lib/features/update/presentation/update_gate.dart` (create) | Launch trigger widget (wraps app) |
| `lib/main.dart` (modify) | Mount `UpdateGate` in the builder |
| `SETUP.md` (modify) | Document publish flow + applicationId/keystore/FTPS prerequisites |
| `test/features/update/...` (create) | Unit tests for model, decision, repository, provider |

---

## Task 0: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the two packages (resolves latest compatible versions)**

Run:
```bash
cd /Users/kagaw/JuanConnect/rev-app/rev_app
flutter pub add package_info_plus ota_update
```
Expected: `pubspec.yaml` gains `package_info_plus:` and `ota_update:` under `dependencies`; `flutter pub get` runs automatically and succeeds.

- [ ] **Step 2: Verify the project still analyzes**

Run: `flutter analyze`
Expected: No new errors (warnings unrelated to our change are fine).

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): add package_info_plus + ota_update for in-app updates"
```

---

## Task 1: Publish side — gitignore, config template, upload script

**Files:**
- Modify: `.gitignore`
- Create: `publish/.ftp.env.example`
- Create: `publish/ftp_publish.sh`

- [ ] **Step 1: Ignore the real FTP config**

Append to `.gitignore`:
```
# Self-hosted publish: real FTP credentials (never commit)
publish/.ftp.env
```

- [ ] **Step 2: Create the committed config template**

Create `publish/.ftp.env.example`:
```sh
# Copy to publish/.ftp.env and fill in real values. publish/.ftp.env is gitignored.
# These credentials are used ONLY by ftp_publish.sh on your machine.
# They are NEVER compiled into the app.

FTP_HOST="ftp.yourhost.com"
FTP_USER="youruser"
FTP_PASS="yourpass"

# Remote directory on the FTP server where files are uploaded.
FTP_REMOTE_DIR="/public_html/app"

# Public HTTPS base URL that serves FTP_REMOTE_DIR. The app downloads from here.
HTTPS_BASE_URL="https://yourhost.com/app"

# Prefer explicit FTPS so the password is not sent in cleartext. Set to "false"
# only if your host does not support FTPS.
FTP_USE_FTPS="true"
```

- [ ] **Step 3: Create the publish script**

Create `publish/ftp_publish.sh`:
```bash
#!/usr/bin/env bash
# Build a release APK, generate version.json, and upload both to the FTP server.
# Usage:  ./publish/ftp_publish.sh ["release notes shown in the update dialog"]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$SCRIPT_DIR/.ftp.env"

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: $CONFIG not found. Copy publish/.ftp.env.example to publish/.ftp.env and fill it in." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG"

for var in FTP_HOST FTP_USER FTP_PASS FTP_REMOTE_DIR HTTPS_BASE_URL; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: $var is not set in $CONFIG" >&2
    exit 1
  fi
done

NOTES="${1:-}"

# Parse "version: X.Y.Z+N" from pubspec.yaml -> name X.Y.Z, code N.
VERSION_LINE="$(grep '^version:' "$ROOT_DIR/pubspec.yaml" | awk '{print $2}')"
VERSION_NAME="${VERSION_LINE%%+*}"
VERSION_CODE="${VERSION_LINE##*+}"
if [ "$VERSION_NAME" = "$VERSION_CODE" ]; then
  echo "ERROR: pubspec version '$VERSION_LINE' has no +buildNumber (need X.Y.Z+N)." >&2
  exit 1
fi
echo "Building rev_app $VERSION_NAME (code $VERSION_CODE)..."

# Build release APK with the same env the app expects.
( cd "$ROOT_DIR" && flutter build apk --release --dart-define-from-file=.env )

APK_SRC="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK_SRC" ]; then
  echo "ERROR: expected APK not found at $APK_SRC" >&2
  exit 1
fi

APK_NAME="rev_app-${VERSION_NAME}+${VERSION_CODE}.apk"
APK_URL="${HTTPS_BASE_URL%/}/${APK_NAME}"

# Write version.json (manifest the app reads).
MANIFEST="$ROOT_DIR/build/version.json"
cat > "$MANIFEST" <<EOF
{
  "versionCode": ${VERSION_CODE},
  "versionName": "${VERSION_NAME}",
  "apkUrl": "${APK_URL}",
  "notes": "${NOTES}"
}
EOF

# Upload helper. Uploads to FTP_REMOTE_DIR. Uses explicit FTPS when enabled.
upload() {
  local localfile="$1" remotename="$2"
  local sslflag=""
  if [ "${FTP_USE_FTPS:-true}" = "true" ]; then sslflag="--ssl-reqd"; fi
  curl --fail --ftp-create-dirs $sslflag \
    --user "${FTP_USER}:${FTP_PASS}" \
    -T "$localfile" \
    "ftp://${FTP_HOST}${FTP_REMOTE_DIR%/}/${remotename}"
}

echo "Uploading APK ($APK_NAME)..."
upload "$APK_SRC" "$APK_NAME"

# Upload the manifest LAST so clients never see a manifest pointing at a
# half-uploaded APK.
echo "Uploading version.json..."
upload "$MANIFEST" "version.json"

echo "Done. Manifest -> ${HTTPS_BASE_URL%/}/version.json"
echo "       APK      -> ${APK_URL}"
```

- [ ] **Step 4: Make it executable**

Run: `chmod +x publish/ftp_publish.sh`

- [ ] **Step 5: Syntax-check the script (no upload performed)**

Run: `bash -n publish/ftp_publish.sh`
Expected: No output, exit 0 (valid syntax).

- [ ] **Step 6: Commit**

```bash
git add .gitignore publish/.ftp.env.example publish/ftp_publish.sh
git commit -m "feat(publish): add gitignored FTP publish script + config template"
```

---

## Task 2: Domain model — `AppVersionInfo`

**Files:**
- Create: `lib/features/update/domain/app_version_info.dart`
- Test: `test/features/update/domain/app_version_info_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/update/domain/app_version_info_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/update/domain/app_version_info.dart';

void main() {
  group('AppVersionInfo.fromMap', () {
    test('parses a complete, valid manifest', () {
      final info = AppVersionInfo.fromMap({
        'versionCode': 2,
        'versionName': '1.1.0',
        'apkUrl': 'https://h/app/rev_app-1.1.0+2.apk',
        'notes': 'Fixes',
      });
      expect(info, isNotNull);
      expect(info!.versionCode, 2);
      expect(info.versionName, '1.1.0');
      expect(info.apkUrl, 'https://h/app/rev_app-1.1.0+2.apk');
      expect(info.notes, 'Fixes');
    });

    test('treats empty notes as null', () {
      final info = AppVersionInfo.fromMap({
        'versionCode': 2,
        'versionName': '1.1.0',
        'apkUrl': 'https://h/a.apk',
        'notes': '',
      });
      expect(info!.notes, isNull);
    });

    test('returns null when versionCode is missing or not an int', () {
      expect(
        AppVersionInfo.fromMap(
            {'versionName': '1.1.0', 'apkUrl': 'https://h/a.apk'}),
        isNull,
      );
      expect(
        AppVersionInfo.fromMap({
          'versionCode': '2',
          'versionName': '1.1.0',
          'apkUrl': 'https://h/a.apk',
        }),
        isNull,
      );
    });

    test('returns null when apkUrl is empty', () {
      expect(
        AppVersionInfo.fromMap(
            {'versionCode': 2, 'versionName': '1.1.0', 'apkUrl': ''}),
        isNull,
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/update/domain/app_version_info_test.dart`
Expected: FAIL — `app_version_info.dart` does not exist / `AppVersionInfo` undefined.

- [ ] **Step 3: Write the model**

Create `lib/features/update/domain/app_version_info.dart`:
```dart
import 'package:equatable/equatable.dart';

/// Parsed contents of the hosted `version.json` update manifest.
///
/// [versionCode] is the authoritative integer used for comparison (mirrors the
/// Android `versionCode` / pubspec `+N` build number). [notes] is optional and,
/// when present, is shown in the update dialog.
class AppVersionInfo extends Equatable {
  const AppVersionInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    this.notes,
  });

  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String? notes;

  /// Defensive parse: any missing or wrong-typed required field yields null so
  /// a malformed manifest fails safe instead of crashing the launch check.
  static AppVersionInfo? fromMap(Map<String, dynamic> map) {
    final code = map['versionCode'];
    final name = map['versionName'];
    final url = map['apkUrl'];
    if (code is! int || name is! String || url is! String || url.isEmpty) {
      return null;
    }
    final rawNotes = map['notes'];
    final notes = (rawNotes is String && rawNotes.isNotEmpty) ? rawNotes : null;
    return AppVersionInfo(
      versionCode: code,
      versionName: name,
      apkUrl: url,
      notes: notes,
    );
  }

  @override
  List<Object?> get props => [versionCode, versionName, apkUrl, notes];
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/update/domain/app_version_info_test.dart`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/update/domain/app_version_info.dart test/features/update/domain/app_version_info_test.dart
git commit -m "feat(update): add AppVersionInfo manifest model"
```

---

## Task 3: Domain — pure `decideUpdate` function

**Files:**
- Create: `lib/features/update/domain/update_decision.dart`
- Test: `test/features/update/domain/update_decision_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/update/domain/update_decision_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/update/domain/app_version_info.dart';
import 'package:rev_app/features/update/domain/update_decision.dart';

AppVersionInfo _info(int code) => AppVersionInfo(
      versionCode: code,
      versionName: '1.$code.0',
      apkUrl: 'https://h/a-$code.apk',
    );

void main() {
  group('decideUpdate', () {
    test('null manifest -> upToDate (fail safe, never nag)', () {
      final d = decideUpdate(currentVersionCode: 1, latest: null);
      expect(d.status, UpdateStatus.upToDate);
      expect(d.hasUpdate, isFalse);
    });

    test('newer manifest -> updateAvailable carries the manifest', () {
      final d = decideUpdate(currentVersionCode: 1, latest: _info(2));
      expect(d.status, UpdateStatus.updateAvailable);
      expect(d.hasUpdate, isTrue);
      expect(d.latest!.versionCode, 2);
    });

    test('equal version -> upToDate', () {
      final d = decideUpdate(currentVersionCode: 2, latest: _info(2));
      expect(d.status, UpdateStatus.upToDate);
    });

    test('older manifest -> upToDate (never downgrade)', () {
      final d = decideUpdate(currentVersionCode: 3, latest: _info(2));
      expect(d.status, UpdateStatus.upToDate);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/update/domain/update_decision_test.dart`
Expected: FAIL — `update_decision.dart` / `decideUpdate` undefined.

- [ ] **Step 3: Write the decision function**

Create `lib/features/update/domain/update_decision.dart`:
```dart
import 'package:equatable/equatable.dart';

import 'app_version_info.dart';

enum UpdateStatus { upToDate, updateAvailable }

/// Result of comparing the installed build against the hosted manifest.
class UpdateDecision extends Equatable {
  const UpdateDecision(this.status, [this.latest]);

  final UpdateStatus status;
  final AppVersionInfo? latest;

  bool get hasUpdate => status == UpdateStatus.updateAvailable;

  @override
  List<Object?> get props => [status, latest];
}

/// Pure comparison seam (mirrors `computeRelease`). A null [latest] — a failed
/// or skipped check — is treated as up to date so the app never nags on error.
UpdateDecision decideUpdate({
  required int currentVersionCode,
  required AppVersionInfo? latest,
}) {
  if (latest == null) return const UpdateDecision(UpdateStatus.upToDate);
  if (latest.versionCode > currentVersionCode) {
    return UpdateDecision(UpdateStatus.updateAvailable, latest);
  }
  return UpdateDecision(UpdateStatus.upToDate, latest);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/update/domain/update_decision_test.dart`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/update/domain/update_decision.dart test/features/update/domain/update_decision_test.dart
git commit -m "feat(update): add pure decideUpdate decision function"
```

---

## Task 4: Config — `AppSecrets.updateManifestUrl`

**Files:**
- Modify: `lib/core/config/app_secrets.dart`
- Modify: `.env.example`

- [ ] **Step 1: Add the manifest URL constant**

In `lib/core/config/app_secrets.dart`, add after the `adminRelayUrl` block (after line 48):
```dart

  // Public, read-only HTTPS URL of the self-hosted update manifest (version.json).
  // Safe to embed: it grants no write access. Blank disables update checks.
  static const String updateManifestUrl =
      String.fromEnvironment('UPDATE_MANIFEST_URL');
```

And add to the boolean getters group (near line 50-52):
```dart
  static bool get hasUpdates => updateManifestUrl.isNotEmpty;
```

- [ ] **Step 2: Document it in `.env.example`**

Append to `.env.example`:
```sh
# Self-hosted in-app update check (Android only). Public HTTPS URL of version.json.
# Leave blank to disable update checks. Must match HTTPS_BASE_URL in publish/.ftp.env.
UPDATE_MANIFEST_URL=https://yourhost.com/app/version.json
```

- [ ] **Step 3: Verify analyze passes**

Run: `flutter analyze lib/core/config/app_secrets.dart`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add lib/core/config/app_secrets.dart .env.example
git commit -m "feat(update): add UPDATE_MANIFEST_URL app config"
```

---

## Task 5: Data — `UpdateRepository` over HTTPS

**Files:**
- Create: `lib/features/update/data/update_repository.dart`
- Test: `test/features/update/data/update_repository_test.dart`

- [ ] **Step 1: Write the failing test (uses http's built-in MockClient)**

Create `test/features/update/data/update_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/update/data/update_repository.dart';

const _url = 'https://h/app/version.json';

HttpUpdateRepository _repo(MockClient client) =>
    HttpUpdateRepository(client: client, manifestUrl: _url);

void main() {
  group('HttpUpdateRepository.fetchLatest', () {
    test('valid JSON -> Ok(AppVersionInfo)', () async {
      final client = MockClient((req) async => http.Response(
            '{"versionCode":2,"versionName":"1.1.0","apkUrl":"https://h/a.apk"}',
            200,
          ));
      final result = await _repo(client).fetchLatest();
      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.versionCode, 2);
    });

    test('non-200 -> Err', () async {
      final client = MockClient((req) async => http.Response('nope', 404));
      final result = await _repo(client).fetchLatest();
      expect(result.isOk, isFalse);
    });

    test('malformed manifest -> Err', () async {
      final client = MockClient(
          (req) async => http.Response('{"versionCode":"x"}', 200));
      final result = await _repo(client).fetchLatest();
      expect(result.isOk, isFalse);
    });

    test('non-JSON body -> Err', () async {
      final client =
          MockClient((req) async => http.Response('<html>', 200));
      final result = await _repo(client).fetchLatest();
      expect(result.isOk, isFalse);
    });

    test('network throw -> Err (no exception escapes)', () async {
      final client = MockClient((req) async => throw Exception('offline'));
      final result = await _repo(client).fetchLatest();
      expect(result.isOk, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/update/data/update_repository_test.dart`
Expected: FAIL — `update_repository.dart` / `HttpUpdateRepository` undefined.

- [ ] **Step 3: Write the repository**

Create `lib/features/update/data/update_repository.dart`:
```dart
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/app_version_info.dart';

/// Fetches the hosted update manifest. Implementations never throw — they return
/// a [Result] so a failed update check can be handled silently.
abstract class UpdateRepository {
  Future<Result<AppVersionInfo>> fetchLatest();
}

class HttpUpdateRepository implements UpdateRepository {
  HttpUpdateRepository({
    required http.Client client,
    required String manifestUrl,
  })  : _client = client,
        _manifestUrl = manifestUrl;

  final http.Client _client;
  final String _manifestUrl;

  @override
  Future<Result<AppVersionInfo>> fetchLatest() async {
    try {
      final resp = await _client.get(Uri.parse(_manifestUrl));
      if (resp.statusCode != 200) {
        return Err(UnexpectedFailure(
            'Update check failed (HTTP ${resp.statusCode}).'));
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        return const Err(ValidationFailure('Update manifest is not an object.'));
      }
      final info = AppVersionInfo.fromMap(decoded);
      if (info == null) {
        return const Err(ValidationFailure('Update manifest is malformed.'));
      }
      return Ok(info);
    } catch (e, st) {
      developer.log('fetchLatest failed', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not check for updates.'));
    }
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/update/data/update_repository_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/update/data/update_repository.dart test/features/update/data/update_repository_test.dart
git commit -m "feat(update): add HttpUpdateRepository returning Result"
```

---

## Task 6: Presentation — providers + `updateCheckProvider`

**Files:**
- Create: `lib/features/update/presentation/update_providers.dart`
- Test: `test/features/update/presentation/update_providers_test.dart`

- [ ] **Step 1: Write the failing test (override the repo; assert the decision)**

Create `test/features/update/presentation/update_providers_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/update/data/update_repository.dart';
import 'package:rev_app/features/update/domain/app_version_info.dart';
import 'package:rev_app/features/update/domain/update_decision.dart';
import 'package:rev_app/features/update/presentation/update_providers.dart';

class _FakeRepo implements UpdateRepository {
  _FakeRepo(this._result);
  final Result<AppVersionInfo> _result;
  @override
  Future<Result<AppVersionInfo>> fetchLatest() async => _result;
}

void main() {
  test('updateCheckProvider returns updateAvailable when repo reports newer',
      () async {
    final container = ProviderContainer(overrides: [
      updateRepositoryProvider.overrideWithValue(
        _FakeRepo(const Ok(AppVersionInfo(
          versionCode: 99,
          versionName: '9.9.9',
          apkUrl: 'https://h/a.apk',
        ))),
      ),
      currentVersionCodeProvider.overrideWith((ref) async => 1),
      isUpdateSupportedPlatformProvider.overrideWithValue(true),
    ]);
    addTearDown(container.dispose);

    final decision = await container.read(updateCheckProvider.future);
    expect(decision.status, UpdateStatus.updateAvailable);
    expect(decision.latest!.versionCode, 99);
  });

  test('updateCheckProvider short-circuits to upToDate on unsupported platform',
      () async {
    final container = ProviderContainer(overrides: [
      updateRepositoryProvider.overrideWithValue(
        _FakeRepo(const Err(UnexpectedFailure('should not be called'))),
      ),
      currentVersionCodeProvider.overrideWith((ref) async => 1),
      isUpdateSupportedPlatformProvider.overrideWithValue(false),
    ]);
    addTearDown(container.dispose);

    final decision = await container.read(updateCheckProvider.future);
    expect(decision.status, UpdateStatus.upToDate);
  });

  test('updateCheckProvider returns upToDate when repo errs (fail safe)',
      () async {
    final container = ProviderContainer(overrides: [
      updateRepositoryProvider.overrideWithValue(
        _FakeRepo(const Err(UnexpectedFailure('offline'))),
      ),
      currentVersionCodeProvider.overrideWith((ref) async => 1),
      isUpdateSupportedPlatformProvider.overrideWithValue(true),
    ]);
    addTearDown(container.dispose);

    final decision = await container.read(updateCheckProvider.future);
    expect(decision.status, UpdateStatus.upToDate);
  });
}
```

> Note: `updateRepositoryProvider` is typed `Provider<UpdateRepository?>`. `overrideWithValue` accepts the non-null fake here.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/update/presentation/update_providers_test.dart`
Expected: FAIL — `update_providers.dart` / providers undefined.

- [ ] **Step 3: Write the providers**

Create `lib/features/update/presentation/update_providers.dart`:
```dart
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/config/app_secrets.dart';
import '../data/update_repository.dart';
import '../domain/update_decision.dart';

/// Shared HTTP client for the update check. Closed when the provider scope is
/// disposed. Overridable in tests.
final updateHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Null when no manifest URL is configured (update checks disabled).
final updateRepositoryProvider = Provider<UpdateRepository?>((ref) {
  if (!AppSecrets.hasUpdates) return null;
  return HttpUpdateRepository(
    client: ref.watch(updateHttpClientProvider),
    manifestUrl: AppSecrets.updateManifestUrl,
  );
});

/// The running build's versionCode (pubspec `+N`). Overridable in tests.
final currentVersionCodeProvider = FutureProvider<int>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return int.tryParse(info.buildNumber) ?? 0;
});

/// Whether self-hosted updates apply to this platform. Android only; iOS/web
/// are no-ops (Apple forbids sideload-update). Overridable in tests.
final isUpdateSupportedPlatformProvider = Provider<bool>((ref) {
  try {
    return Platform.isAndroid;
  } catch (_) {
    return false; // web: dart:io Platform throws.
  }
});

/// One-shot launch check. Fails safe to [UpdateStatus.upToDate] on unsupported
/// platforms, missing config, or any repository error.
final updateCheckProvider = FutureProvider<UpdateDecision>((ref) async {
  if (!ref.watch(isUpdateSupportedPlatformProvider)) {
    return const UpdateDecision(UpdateStatus.upToDate);
  }
  final repo = ref.watch(updateRepositoryProvider);
  if (repo == null) return const UpdateDecision(UpdateStatus.upToDate);

  final current = await ref.watch(currentVersionCodeProvider.future);
  final result = await repo.fetchLatest();
  return result.when(
    ok: (latest) =>
        decideUpdate(currentVersionCode: current, latest: latest),
    err: (_) => const UpdateDecision(UpdateStatus.upToDate),
  );
});
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/update/presentation/update_providers_test.dart`
Expected: PASS (all 3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/update/presentation/update_providers.dart test/features/update/presentation/update_providers_test.dart
git commit -m "feat(update): add update check providers (platform/config fail-safe)"
```

---

## Task 7: Presentation — installer wrapper + dismissible prompt

**Files:**
- Create: `lib/features/update/presentation/update_installer.dart`
- Create: `lib/features/update/presentation/update_prompt.dart`

> UI-only glue around `ota_update`; no unit tests (device-dependent install). Verified by `flutter analyze` + manual run.

- [ ] **Step 1: Write the installer wrapper**

Create `lib/features/update/presentation/update_installer.dart`:
```dart
import 'package:ota_update/ota_update.dart';

/// Thin wrapper over the ota_update plugin: downloads the APK over HTTPS and
/// launches the Android system installer, streaming progress events.
class UpdateInstaller {
  const UpdateInstaller();

  Stream<OtaEvent> downloadAndInstall(String apkUrl) {
    return OtaUpdate().execute(apkUrl, destinationFilename: 'rev_app-update.apk');
  }
}
```

- [ ] **Step 2: Write the prompt dialog**

Create `lib/features/update/presentation/update_prompt.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import '../../../core/theme/app_tokens.dart';
import '../domain/app_version_info.dart';
import 'update_installer.dart';

/// Shows the dismissible "Update available" confirmation dialog. Returns when
/// the dialog is closed. Tapping "Update" downloads + installs in place,
/// showing live progress; "Later" dismisses (re-checked next launch).
Future<void> showUpdatePrompt(
  BuildContext context,
  AppVersionInfo latest, {
  UpdateInstaller installer = const UpdateInstaller(),
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _UpdateDialog(latest: latest, installer: installer),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.latest, required this.installer});

  final AppVersionInfo latest;
  final UpdateInstaller installer;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress; // null = not started; 0..1 while downloading.
  String? _error;

  void _startUpdate() {
    setState(() {
      _progress = 0;
      _error = null;
    });
    widget.installer.downloadAndInstall(widget.latest.apkUrl).listen(
      (event) {
        if (!mounted) return;
        if (event.status == OtaStatus.DOWNLOADING) {
          final pct = int.tryParse(event.value ?? '');
          if (pct != null) setState(() => _progress = pct / 100.0);
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _error = 'Update failed. Please try again later.';
            _progress = null;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloading = _progress != null;

    return AlertDialog(
      icon: const Icon(Icons.system_update_alt_rounded),
      title: Text('Update available (${widget.latest.versionName})'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.latest.notes?.isNotEmpty == true
                ? widget.latest.notes!
                : 'A newer version of the app is ready to install.',
            style: theme.textTheme.bodyMedium,
          ),
          if (downloading) ...[
            const SizedBox(height: AppTokens.md),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: AppTokens.xs),
            Text('Downloading… ${((_progress ?? 0) * 100).round()}%',
                style: theme.textTheme.bodySmall),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppTokens.md),
            Text(_error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ],
        ],
      ),
      actions: downloading
          ? const [
              // No actions mid-download; the installer takes over once complete.
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: _startUpdate,
                child: const Text('Update'),
              ),
            ],
    );
  }
}
```

- [ ] **Step 3: Verify analyze passes**

Run: `flutter analyze lib/features/update/presentation/update_installer.dart lib/features/update/presentation/update_prompt.dart`
Expected: No errors. (If `OtaStatus`/`OtaEvent` member names differ in the resolved `ota_update` version, fix the references per the package API — confirm with `cat .dart_tool/.../ota_update` or the pub.dev docs for the resolved version.)

- [ ] **Step 4: Commit**

```bash
git add lib/features/update/presentation/update_installer.dart lib/features/update/presentation/update_prompt.dart
git commit -m "feat(update): add installer wrapper + dismissible update dialog"
```

---

## Task 8: Wire the launch trigger into the app

**Files:**
- Create: `lib/features/update/presentation/update_gate.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Write the gate widget**

Create `lib/features/update/presentation/update_gate.dart`:
```dart
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
```

- [ ] **Step 2: Mount it in `main.dart`**

In `lib/main.dart`, add the import after line 13 (`import 'routing/app_router.dart';`):
```dart
import 'features/update/presentation/update_gate.dart';
```

Then wrap the existing builder body (lines 51-53) so `UpdateGate` is the outermost wrapper:
```dart
      builder: (context, child) => UpdateGate(
        child: WelcomeGate(
          child: MessagingInitializer(child: child ?? const SizedBox.shrink()),
        ),
      ),
```

- [ ] **Step 3: Verify analyze + full test suite**

Run: `flutter analyze`
Expected: No errors.

Run: `flutter test`
Expected: All tests pass (existing + the new update tests).

- [ ] **Step 4: Commit**

```bash
git add lib/features/update/presentation/update_gate.dart lib/main.dart
git commit -m "feat(update): trigger update check + prompt on app launch (Android)"
```

---

## Task 9: Documentation — publish flow + distribution prerequisites

**Files:**
- Modify: `SETUP.md`

- [ ] **Step 1: Append a distribution section to `SETUP.md`**

Add this section to `SETUP.md`:
```markdown
## Self-hosted distribution & in-app updates (Android only)

The app can update itself from an APK hosted on your own FTP server, served over
HTTPS. iOS is not supported (Apple forbids sideload-update).

### One-time prerequisites (required before the first real release)

1. **Set a real `applicationId`.** `android/app/build.gradle.kts` ships with the
   placeholder `com.example.rev_app`. Change it to your real id (e.g.
   `ph.com.brigada.revapp`) **before** distributing. Android matches updates by
   `applicationId`; changing it after users install means new APKs are treated as
   a different app and cannot update over the old one.
2. **Use one consistent release keystore.** Android rejects an update signed by a
   different key than the installed version. Create a release keystore, wire it
   into `android/app/build.gradle.kts` signing config, and reuse it for every
   release. Debug-signed APKs will not upgrade each other reliably.
3. **Prefer FTPS.** Plain FTP sends the password in cleartext. Keep
   `FTP_USE_FTPS="true"` in `publish/.ftp.env` unless your host lacks FTPS.

### Configure

1. Copy `publish/.ftp.env.example` to `publish/.ftp.env` and fill in your FTP
   host/user/pass, `FTP_REMOTE_DIR`, and `HTTPS_BASE_URL`. This file is
   gitignored and is the ONLY place FTP credentials live — never in the app.
2. In `.env`, set `UPDATE_MANIFEST_URL` to `<HTTPS_BASE_URL>/version.json`.

### Release a new version

1. Bump `version:` in `pubspec.yaml` (the `+N` build number MUST increase — it is
   the value the app compares).
2. Run: `./publish/ftp_publish.sh "What changed in this release"`
   This builds the release APK, writes `version.json`, and uploads both (manifest
   last). Installed apps will prompt to update on their next launch.
```

- [ ] **Step 2: Commit**

```bash
git add SETUP.md
git commit -m "docs(update): document FTP publish flow + distribution prerequisites"
```

---

## Final Verification

- [ ] **Step 1: Full analyze**

Run: `flutter analyze`
Expected: No errors.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: All pass, including the new `test/features/update/` tests.

- [ ] **Step 3: Build a release APK end-to-end (no upload)**

Run: `flutter build apk --release --dart-define-from-file=.env`
Expected: Build succeeds (proves the new deps + code compile in release mode).

---

## Notes for the implementer

- **TDD order matters:** domain (Tasks 2-3) → data (Task 5) → presentation (Task 6) → UI glue (Tasks 7-8). The pure functions (`AppVersionInfo.fromMap`, `decideUpdate`) and the repository are the unit-test seams; the UI/installer are verified by analyze + manual run.
- **`ota_update` API drift:** the plugin bundles its own `FileProvider` + `REQUEST_INSTALL_PACKAGES` permission via manifest merge, so AndroidManifest.xml likely needs no manual edits. If a build error names a missing permission or provider, follow the resolved version's README. Member names (`OtaStatus.DOWNLOADING`, `OtaEvent.value`) are from the current API — verify against the version `flutter pub add` resolved.
- **Do not** put FTP credentials in `.env`, `app_secrets.dart`, or any committed file. They live only in `publish/.ftp.env`.
```