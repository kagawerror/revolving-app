# Self-hosted FTP publish + in-app HTTPS auto-update — Design

**Date:** 2026-06-06
**Status:** Approved (design); pending implementation plan
**Platform scope:** Android only (iOS/web are explicit no-ops)

## Problem

We distribute `rev_app` outside the Google Play Store. We want to:

1. Publish a release APK to our own FTP server from the developer's machine.
2. Serve that APK (and a small version manifest) to clients over **HTTPS**.
3. Have the installed app detect when a newer version exists and let the user
   download + install it in-app.

## Non-negotiable security constraint

FTP credentials (host/user/password) grant full read/write/delete over the file
server. They **must never** ship inside the app.

`--dart-define` / `String.fromEnvironment` values are compiled into the APK as
plaintext and are trivially extractable (`unzip` + `strings`). This is exactly
why the existing `AppSecrets` only carries an *unsigned* Cloudinary preset (see
`lib/core/config/app_secrets.dart:1-3`). We follow the same discipline:

- **FTP credentials** live only in `publish/.ftp.env` on the developer's machine
  (gitignored). They are used by a publish *script*, never by the app.
- **The app** only knows the public, read-only HTTPS URL of the manifest. Safe to
  embed.

## Architecture — two isolated halves

```
PUBLISH (developer Mac)                       UPDATE (users' Android phones)
┌───────────────────────────┐                 ┌──────────────────────────────┐
│ publish/.ftp.env (secret)  │ gitignored      │ AppSecrets.updateManifestUrl │
│   FTP_HOST/USER/PASS       │                 │   (public HTTPS, safe)       │
│ publish/ftp_publish.sh     │                 │                              │
│   1. flutter build apk     │  curl FTP(S)    │ on launch (Android only):    │
│   2. generate version.json │ ───────────────►│   1. GET version.json (HTTPS)│
│   3. upload APK + manifest │   served over   │   2. decideUpdate()          │
└───────────────────────────┘   HTTPS by host  │   3. dialog → download → install
                                                └──────────────────────────────┘
```

The FTP password exists only in `publish/.ftp.env`. It is never in the app, never
in git.

## Component 1 — Publish side (`publish/` folder)

- **`publish/.ftp.env.example`** (committed template):
  ```sh
  FTP_HOST="ftp.yourhost.com"
  FTP_USER="youruser"
  FTP_PASS="yourpass"
  FTP_REMOTE_DIR="/public_html/app"             # where files land on the server
  HTTPS_BASE_URL="https://yourhost.com/app"     # public download base
  FTP_USE_FTPS="true"                            # prefer FTPS; password not cleartext
  ```
- **`publish/.ftp.env`** — real values, **gitignored** (add `publish/.ftp.env`
  to `.gitignore`).
- **`publish/ftp_publish.sh`** — POSIX/bash script:
  1. `set -euo pipefail`; load `publish/.ftp.env`; fail clearly if any var is missing.
  2. Parse `version: X.Y.Z+N` from `pubspec.yaml` → `versionName=X.Y.Z`,
     `versionCode=N`.
  3. `flutter build apk --release --dart-define-from-file=.env`.
  4. Copy build output to `rev_app-<versionName>+<versionCode>.apk`.
  5. Generate `version.json` (schema below) with `apkUrl = HTTPS_BASE_URL + "/" + filename`.
     Optional release notes via `$1` / `--notes`.
  6. Upload APK then `version.json` via `curl -T <file> ftp(s)://...` with
     `--user "$FTP_USER:$FTP_PASS"`, `--ftp-create-dirs`, and `--ssl-reqd` when
     `FTP_USE_FTPS=true`. Upload the manifest **last** so clients never see a new
     manifest pointing at an APK that isn't fully uploaded yet.

## Component 2 — Manifest (`version.json`, generated, hosted on the server)

```json
{
  "versionCode": 2,
  "versionName": "1.1.0",
  "apkUrl": "https://yourhost.com/app/rev_app-1.1.0+2.apk",
  "notes": "What changed in this release"
}
```

`versionCode` is the authoritative integer used for comparison. `notes` is
optional (shown in the dialog when present).

## Component 3 — App side (`lib/features/update/`, the 3-layer feature pattern)

- **`domain/app_version_info.dart`** — immutable `Equatable` model with
  `versionCode` (int), `versionName` (String), `apkUrl` (String), `notes`
  (String?). `fromMap` parses the manifest JSON defensively (missing/wrong-typed
  fields → safe failure, not a crash).
- **`domain/update_decision.dart`** — pure function, the testable seam (mirrors
  `computeRelease`):
  ```dart
  enum UpdateStatus { upToDate, updateAvailable }

  class UpdateDecision { final UpdateStatus status; final AppVersionInfo? latest; ... }

  UpdateDecision decideUpdate({
    required int currentVersionCode,
    required AppVersionInfo? latest,
  });
  // null latest        -> upToDate (fail safe: never nag on a failed check)
  // latest.code  > cur -> updateAvailable
  // latest.code <= cur -> upToDate
  ```
- **`data/update_repository.dart`** — `UpdateRepository` interface +
  `HttpUpdateRepository` impl. Fetches the manifest over HTTPS via the existing
  `http` package, parses via `AppVersionInfo.fromMap`, returns
  **`Result<AppVersionInfo>`** (`Ok`/`Err`). Catches everything, `developer.log`s
  the real error, returns a user-safe `Err` — raw exceptions never escape.
- **`presentation/update_providers.dart`** — Riverpod wiring:
  - `updateRepositoryProvider` (depends on an injectable `http.Client` provider so
    tests can override it),
  - `currentVersionProvider` (`FutureProvider<int>` via `package_info_plus`),
  - `updateCheckProvider` (`FutureProvider<UpdateDecision>` combining the two;
    returns `upToDate` on non-Android or on `Err`).
- **`presentation/update_prompt.dart`** — a **dismissible confirmation dialog**
  ("Update available" → **Update** / **Later**), styled to the app theme (not a
  bare `AlertDialog`). "Update" streams download progress (via `ota_update`) and
  launches the system installer; "Later" dismisses and we re-check next launch.

### Wiring
- Trigger the check once on app launch from the authenticated shell (after the
  router lands a logged-in user), guarded by `Platform.isAndroid`.
- The check is non-blocking: UI renders normally; the dialog appears only if
  `updateAvailable`.

## New dependencies
- `package_info_plus` — read the running app's `versionCode`.
- `ota_update` — Android download-to-file + launch installer; bundles the
  `FileProvider` + `REQUEST_INSTALL_PACKAGES` plumbing, keeping AndroidManifest
  changes minimal. (Verify during implementation whether any manifest entry is
  still required after the plugin merge.)

## Error handling
- **Android only.** iOS/web → silent no-op (Apple forbids sideload-update).
- Network failure, non-200, malformed JSON → logged, `Err`, **app continues**. An
  update check must never block or crash the app.
- Download/install failure → user-visible error in the dialog; app stays usable.

## Testing (TDD, the `computeRelease` style)
- Pure unit tests for `decideUpdate`: newer-available, equal, older, null manifest.
- `AppVersionInfo.fromMap`: valid map, missing fields, wrong types.
- `HttpUpdateRepository` against a mocked `http.Client`: good JSON → `Ok`,
  garbage/non-200 → `Err`.
- Provider test: override repo + current version, assert the `UpdateDecision`;
  assert non-Android short-circuits to `upToDate`.

## Distribution prerequisites (NOT this feature's code — documented follow-ups)

These are required for the mechanism to work in production. Tracked here and to be
added to `SETUP.md`; handled as a separate small task unless folded in later.

1. **Change `applicationId` off the default `com.example.rev_app`** *before* the
   first real release. Android matches updates by `applicationId`; changing it
   after users install means new APKs are treated as a different app and cannot
   update over the old one. Choose a real id (e.g. `ph.com.brigada.revapp`).
2. **Consistent release keystore.** Android rejects an update signed by a
   different key than the installed version. The first self-hosted APK and every
   subsequent one must be release-signed with the *same* keystore.
3. **Prefer FTPS over plain FTP.** Plain FTP transmits the password in cleartext.
   The publish script defaults to FTPS (`--ssl-reqd`) when `FTP_USE_FTPS=true`.
4. **Google Play policy:** if the app is *also* distributed via Play, Play forbids
   self-updating via sideloaded APK. This channel is for internal/self-hosted
   distribution only.

## Out of scope (YAGNI)
- Forced / minimum-version enforcement (manifest could later add `minVersionCode`;
  not built now — updates are optional/dismissible).
- Delta/patch updates, staged rollouts, CI-based publishing.
- iOS distribution.
```