# Connectivity Banner — Design

**Date:** 2026-06-13
**Branch:** feat/offline-first
**Status:** Approved (pending spec review)

## Goal

Show a status banner on the home screens that tells the user, at a glance, when
the app loses and regains connectivity:

- **Offline** → a **red** banner, shown the whole time connectivity is down.
- **Back online** → a **green** banner, shown briefly on reconnect, then it
  disappears on its own.

## Background — what already exists

- `connectivityProvider` (`StreamProvider<bool>`) in
  `lib/features/sync/presentation/sync_providers.dart` already detects
  online/offline by watching whether the user's own Firestore snapshot comes
  from cache (`!snap.metadata.isFromCache`). It emits `false` while signed out.
- `OfflineBanner` (in `lib/features/sync/presentation/pending_sync_indicator.dart`)
  already renders a calm, **neutral** banner while offline, and is mounted in
  `InchargeHomeBody` and `ApproverHomeBody` — but **not** `AdminHomeBody`.
- `RoleShellScreen` (`lib/routing/role_shell_screen.dart`) is the shared
  `Scaffold` that wraps all three role home bodies in an `IndexedStack`.
- `StatusPill.colorsFor(StatusTone, ColorScheme)` is the app's
  semantic tone→(bg, fg) color mapping. `StatusTone.danger` → red,
  `StatusTone.success` → green, theme-adaptive and contrast-safe.

## Design decisions (from brainstorming)

1. **Online banner is transient, auto-dismiss.** Being online is the normal
   state, so a permanent "you're online" banner would be noise. The green
   banner fires only on the offline→online *edge* and auto-collapses after
   ~3 seconds.
2. **Lift to the shell.** Banner rendering moves into `RoleShellScreen` so
   admin, incharge, and approver all behave identically from one definition.
   The per-body `OfflineBanner` usages are removed.
3. **Colors:** offline = **red** (`StatusTone.danger`), online = **green**
   (`StatusTone.success`). This intentionally overrides the original widget's
   neutral choice, per explicit user instruction. Colors are pulled from the
   theme via `StatusPill.colorsFor`, not hardcoded.

## Component

### `ConnectivityBanner` (new `ConsumerStatefulWidget`)

Lives in `pending_sync_indicator.dart`. The old public `OfflineBanner` widget
is **deleted** — its only two call sites (incharge/approver bodies) are being
removed, so nothing else references it. Renders one of three
states inside an `AnimatedSize` (220ms, `easeOutCubic`, `topCenter`), matching
the existing banner's geometry (`AppTokens` margins, `AppTokens.brField`):

| Internal state | Tone | Icon | Copy |
|---|---|---|---|
| `offline` | `danger` (red) | `Icons.cloud_off_rounded` | "Offline — changes saved on this device." |
| `backOnline` | `success` (green) | `Icons.cloud_done_rounded` | "Back online — syncing your changes." |
| `hidden` | — | — | collapsed `SizedBox(width: double.infinity)` |

**Edge + timer logic (the heart of the feature):**

- `ref.listen(connectivityProvider, (prev, next) { ... })` gives both previous
  and current online value.
- On **false→true** edge: set a `_showBackOnline` flag and start a 3s `Timer`
  that clears it (→ `hidden`).
- On any transition to **offline**: cancel the timer and clear `_showBackOnline`
  (so a stale "Back online" can never linger after we've dropped offline again).
- `dispose()` cancels the timer.

**Which-state-to-show** is extracted into a pure helper so it's unit-testable
without a clock:

```dart
enum ConnBannerState { offline, backOnline, hidden }

ConnBannerState connBannerState({
  required bool online,
  required bool showBackOnline,
}) =>
    !online
        ? ConnBannerState.offline
        : (showBackOnline ? ConnBannerState.backOnline : ConnBannerState.hidden);
```

Accessibility: `Semantics(liveRegion: true, label: ...)` on each visible state,
as the current `OfflineBanner` already does.

### `RoleShellScreen` change

Insert a single `const ConnectivityBanner()` in the body `Column`, above the
`IndexedStack`. Remove the `OfflineBanner` from `InchargeHomeBody` and
`ApproverHomeBody`.

## Testing

- **Unit:** `connBannerState` truth table — offline→`offline`,
  online+flag→`backOnline`, online+no-flag→`hidden`.
- **Widget (`fakeAsync`):** override `connectivityProvider`, drive
  offline→online, assert the green banner mounts, then assert it collapses after
  the 3s timer elapses. Drive online→offline mid-window and assert the green
  banner is cancelled immediately in favor of the red one.

## Out of scope

- No change to `connectivityProvider`, the outbox, or the sync engine.
- No change to `PendingSyncBadge` / `SyncStatusSheet`.
- No new connectivity package — the Firestore-metadata probe stays the source.
