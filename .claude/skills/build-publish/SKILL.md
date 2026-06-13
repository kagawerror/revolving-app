---
name: build-publish
description: Use when shipping, releasing, publishing, deploying, or pushing a new version of rev_app to users — "cut a build", "release to production", "roll out an update", "upload a new APK", or "bump and ship", even if the words "build" or "FTP" aren't said. Android self-hosted distribution (FTP upload + HTTPS auto-update), not Play Store.
---

# build-publish — release & distribute rev_app (Android)

## Overview

rev_app ships outside the Play Store. You build a signed release APK, upload it
plus a `version.json` manifest to the FTP server; installed phones poll the
manifest over HTTPS on launch and prompt to install when the build number rises.

```
PUBLISH (dev machine)                      UPDATE (users' Android phones)
publish/.ftp.env  → FTP creds (upload)     AppSecrets.updateManifestUrl (HTTPS)
publish/ftp_publish.sh:                     on launch (Android only):
  1. flutter build apk --release             1. GET version.json
  2. write version.json                       2. compare versionCode
  3. upload APK, then manifest LAST          3. dialog → download → ota_update install
```

The FTP password is the **upload** key only — it lives in `publish/.ftp.env`
(gitignored) and is NEVER compiled into the app. Clients download from
`HTTPS_BASE_URL`. Do not add FTP creds to `AppSecrets` / `String.fromEnvironment`.

## The one tool: `publish/ftp_publish.sh`

This tracked script is the **only** publish mechanism. Do NOT write a second
publish script under this skill — a duplicate caused inconsistent APK filenames
and creds on the server. If you find a skill-local `scripts/publish.sh`, delete
it and use `publish/ftp_publish.sh`.

## Preflight (run first, in order)

```sh
git fetch && git status -sb | head -1            # 1. branch must be in sync with origin
ls lib/features/update/ >/dev/null 2>&1 && echo "updater: present" || echo "updater: MISSING"
test -f publish/.ftp.env && echo "creds: present" || echo "creds: MISSING"
```

1. **Behind origin?** Sync first. The branch has silently fallen 20 commits
   behind before, making already-merged code look "untracked" and producing a
   stale build. Never publish from a branch behind its remote.
2. **`updater: MISSING`** → existing installs can't auto-detect updates. You can
   still build/upload, but say so. Design/plan:
   `docs/superpowers/specs/2026-06-06-ftp-publish-inapp-update-design.md`.
3. **`creds: MISSING`** → `cp publish/.ftp.env.example publish/.ftp.env` and fill
   in. For this server set `FTP_USE_FTPS="false"` (it speaks **plain FTP only**;
   FTPS uploads fail).

## Workflow

### 1. Bump the version — the gate that makes updates work
Clients compare the integer build number `+N`. If it doesn't strictly increase
versus the **last published** build, nothing updates.

- Check what's live: `curl -fsSL "<HTTPS_BASE_URL>/version.json"` → note `versionCode`.
- Confirm the new version with the user (a release decision): bug-fix → bump `+N`
  only (`1.0.1+3` → `1.0.1+4`); user-facing change → bump name too
  (`1.0.1+3` → `1.1.0+4`).
- Edit the `version:` line in `pubspec.yaml`. `+N` MUST exceed the live `versionCode`.

### 2. Build & publish
Release notes are arg 1 (shown in the in-app update dialog):
```sh
bash publish/ftp_publish.sh "What changed in this release"
```
It builds `flutter build apk --release --dart-define-from-file=.env`, writes
`build/version.json`, uploads `rev_app-<name>+<code>.apk`, then the manifest LAST.

### 3. Verify the publish
```sh
curl -fsSL "<HTTPS_BASE_URL>/version.json"          # versionCode == the build you shipped?
curl -fsI  "<apkUrl from manifest>" | grep -i '^HTTP'  # → 200
```
APKs are named with a **dash** (`rev_app-1.0.1-5.apk`), not `+`. A literal `+`
is valid in a URL path and works in-app (ota_update sends it verbatim), but
browsers and chat apps decode `+` to a space on manual download → 404. Dash is
safe everywhere. If you see a `+`-named APK from an older release, that's why.

### 4. Tag (optional)
`git add pubspec.yaml && git commit -m "release: vX.Y.Z+N" && git tag vX.Y.Z+N`
(don't push unless asked).

## Bootstrap caveat (read once)

The in-app updater only runs on builds that **already contain**
`lib/features/update/`. The first such build can't have been auto-delivered —
it must be installed **manually once**. Auto-update works from the *next* bump on.

## Distribution prerequisites (must stay true)

- **applicationId** = `ph.com.brigada.revapp` (not `com.example.*`). Updates match
  by applicationId; changing it orphans old installs.
- **One release keystore.** Every APK must be signed by the same key
  (`android/key.properties` → off-repo `.jks`); a different key (or debug signing)
  is rejected as an update. The keystore is irreplaceable — back it up off-machine.
- **No Play Store.** Play forbids self-updating via sideloaded APK; this channel is
  internal/self-hosted only.

## Troubleshooting

- **Clients don't update** → `+N` didn't increase; installed app predates
  `lib/features/update/`; `UPDATE_MANIFEST_URL` in the build ≠ upload location; or
  the installed APK is signed by a different key.
- **`curl` 530 / login error** → wrong creds in `publish/.ftp.env`, or
  `FTP_USE_FTPS` true on a plain-FTP host (set `false`).
- **`flutter build apk` fails parsing `.env`** → a line isn't `KEY=VALUE`.
- **Manifest shows old versionCode** → host caching, or the manifest upload failed;
  re-run (the script uploads the manifest last).
- **R8 launch crash** → release minification must stay disabled in
  `android/app/build.gradle.kts` (`isMinifyEnabled = false`); see SETUP.md / the
  self-hosted-distribution notes.
