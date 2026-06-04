# Design — "Revolving" Visual System, Profile & Theming

- **Date:** 2026-06-04
- **Status:** Approved (brainstorming) — pending spec review
- **Author:** Claude (brainstorming session with @alan.ocsin)

## 1. Goal

Transform `rev_app` from a functional-but-plain Material 3 app into a **bold, vibrant, world-class** experience across **every module**, and ship a new **Profile** feature where each user can:

- Upload a **circular profile photo** (camera/gallery → crop → Cloudinary).
- Choose a **theme mode** (System / Light / Dark) and an **accent color** from a curated palette.
- Have those preferences **persisted to their Firebase user document** and applied at runtime across the whole app.

## 2. Decisions (locked during brainstorming)

| Topic | Decision |
| --- | --- |
| Aesthetic direction | **Bold & vibrant** (strong accent usage, gradients, motion, large rounded shapes) — keeps the forest-green brand as the default accent. |
| Theming scope | **Light / Dark / System** mode **+ curated accent presets** (no free color picker). |
| Redesign scope | **All modules, full polish** — sequenced so value lands early. |
| Profile photo | **Pick → crop to circle → compress → Cloudinary**; store `photoUrl` on the user doc. |
| Tooling | Add `google_fonts`, `flutter_animate`, `shimmer`, `cached_network_image`, `image_cropper`. |
| Mascot (Revvy) | **Woven through key moments** — empty states, success confirmations, onboarding. |
| Data model | **Flat fields** on `/users/{uid}`: `photoUrl`, `themeMode`, `accentId`. |
| Typeface | **Plus Jakarta Sans** (via `google_fonts`). |
| Sequencing | Foundation → Profile/Theming → Dashboard → Requests → remaining modules. |

## 3. Chosen approach

**Centralized design system + runtime theming.** A single `lib/core/theme/` token/typography/palette layer and a single `lib/core/widgets/` shared component library. Every feature module is refactored to consume them. A `themeControllerProvider` hydrates from the authenticated user and drives `MaterialApp.router`.

Rejected alternatives: per-screen restyling (drift/duplication across all modules), and adopting `flex_color_scheme` (heavyweight; Material 3 seeds + a thin token layer already meet the need).

## 4. Architecture

### 4.1 Design foundation — `lib/core/theme/`

- **`app_accents.dart`** — `AccentOption { String id; String label; Color seed; }` and a `const` list of ~8 presets:
  - `forest` (`0xFF0B6E4F`, **default**), `indigo`, `violet`, `sunset`, `amber`, `teal`, `rose`, `slate`.
  - `AppAccents.byId(String?)` returns the matching option, **falling back to `forest`** for unknown/null ids (pure, unit-tested).
- **`app_typography.dart`** — Plus Jakarta Sans `TextTheme` built via `google_fonts`; strong display weights, legible body.
- **`app_tokens.dart`** — radii (cards 20–24, pills 999), spacing scale, soft-shadow/elevation presets, and accent **gradient** builders derived from the active seed.
- **`app_theme.dart`** — refactor the current single `light()` into `AppTheme.light(Color seed)` and `AppTheme.dark(Color seed)`. Both `useMaterial3`, with themed `AppBarTheme`, `CardTheme`, `FilledButtonTheme`, `ChipTheme`, `InputDecorationTheme`, `NavigationBarTheme`. Dark mode is a true dark `ColorScheme.fromSeed(brightness: dark)`, not an inversion.

### 4.2 Shared widget library — `lib/core/widgets/` (new)

| Widget | Purpose |
| --- | --- |
| `AppScaffold` | Branded/gradient app bar with an avatar action that routes to `/profile`. |
| `BalanceHeroCard` | Gradient hero showing fund balance — dashboard centerpiece. |
| `StatCard` | Promoted from dashboard; animated count-in metric card. |
| `SurfaceCard` | Standard rounded, soft-shadowed content card. |
| `SectionHeader` | Consistent section titles + optional trailing action. |
| `StatusPill` | Status chip driven off `RequestStatus` / `ReplenishmentStatus`. |
| `AppAvatar` | `cached_network_image` photo with initials fallback. |
| `EmptyState` | Illustration (Revvy) + message + optional CTA. |
| `SuccessOverlay` | Celebratory confirmation (Revvy) for released/signed moments. |
| `Skeleton` | `shimmer` loading placeholders. |
| `AppListTile` | Themed list row used across modules. |

Motion via `flutter_animate` (staggered list entrances, press-scale). Network images via `cached_network_image`.

### 4.3 Data model + persistence

`AppUser` (`lib/features/auth/domain/app_user.dart`) gains:

```dart
final String? photoUrl;       // Cloudinary secure_url, null when unset
final ThemeMode themeMode;    // default ThemeMode.system
final String accentId;        // default 'forest'
```

- Update `fromMap`, `toMap`, and `toCreateMap` (bootstrap writes defaults: `themeMode: system`, `accentId: forest`, `photoUrl: null`).
- `themeMode` is serialized as a string (`'system' | 'light' | 'dark'`) with a safe parse.

`AuthRepository` gains:

```dart
Future<Result<void>> updateProfile({
  String? displayName,
  String? photoUrl,
  ThemeMode? themeMode,
  String? accentId,
});
```

- Implemented in `FirebaseAuthRepository` as a **merge** write to `/users/{uid}` of only the provided fields. Catches and returns `Result` per repo convention; never throws.

### 4.4 Firestore rules (security-critical)

Add an update rule for `users/{uid}` allowing the **owner** to write **only** the self-service fields and nothing else:

- Allowed to change: `displayName`, `photoUrl`, `themeMode`, `accentId`.
- **Immutable to the user:** `role`, `companyId` (admin-only, unchanged from current behavior).

Enforced twice (same philosophy as the state machines): `updateProfile` never sends `role`/`companyId`, **and** the rule rejects any write that touches them. Implementation detail: use a diff-of-changed-keys check (e.g. `request.resource.data.diff(resource.data).affectedKeys()` restricted to the allowed set, plus equality checks on `role`/`companyId`).

### 4.5 Runtime theming

- `themeControllerProvider` — a Riverpod `Notifier` holding `{ ThemeMode mode, Color seed }`.
- Hydrates from `currentUserProvider`: when an `AppUser` is present, `mode = user.themeMode`, `seed = AppAccents.byId(user.accentId).seed`. Pre-login / logged-out uses the brand default (`system`, `forest`).
- `MaterialApp.router` consumes it: `theme: AppTheme.light(seed)`, `darkTheme: AppTheme.dark(seed)`, `themeMode: mode`.
- Profile edits update the controller **optimistically/instantly**, then persist via `updateProfile`. If the persist fails, surface the failure (snackbar) but keep the optimistic UI — the next `currentUser` stream emission is the source of truth.

### 4.6 Profile feature — `lib/features/profile/` (new)

- **`presentation/profile_screen.dart`**
  - Circular `AppAvatar` — tap → `image_picker` → `image_cropper` (circle/square) → `flutter_image_compress` → Cloudinary upload (`avatars` folder) → `updateProfile(photoUrl: ...)`.
  - Editable display name (saved via `updateProfile`).
  - Read-only role + company badges.
  - Theme-mode segmented control (System / Light / Dark).
  - Accent swatch grid with live preview (updates `themeController` immediately).
  - Sign out (reuses existing `signOutProvider`).
- **`presentation/profile_controller.dart`** — manages avatar upload + save state (`idle/uploading/error`), orchestrates picker → cropper → compress → upload → persist.
- **`presentation/profile_providers.dart`** — an avatar-scoped `CloudinaryUploader` provider (reuses the existing uploader class with the `avatars` folder), plus controller wiring.

### 4.7 Routing — `lib/routing/app_router.dart`

- Add `GoRoute(path: '/profile', builder: ProfileScreen)`.
- Avatar action in module app bars routes to `/profile`. No redirect/role changes.

### 4.8 Module redesigns (full polish)

All modules consume the foundation + shared widgets. Sequenced delivery:

1. **Foundation** (theme tokens, typography, accents, shared widgets, runtime theming wiring).
2. **Profile / Theming** (model + rules + repo + screen + route).
3. **Dashboard** — gradient `BalanceHeroCard`, animated stat grid, richer fund-utilization, recent-activity timeline, shimmer loaders, empty states.
4. **Requests** — polished create flow (image-upload card, validation states), request detail with hero proof image + **status timeline**, context-aware actions; incharge/approver homes restyled.
5. **Remaining modules** — Replenishment (list/detail/sign-off + `SuccessOverlay`), Admin/Companies (admin home, create fund, user management), Auth (login + bootstrap), Notifications (alerts bell + list).

## 5. New dependencies

`google_fonts`, `flutter_animate`, `shimmer`, `cached_network_image`, `image_cropper`. `image_cropper` requires platform config (Android `UCropActivity` in manifest, iOS pod) — covered during implementation.

## 6. Testing strategy (TDD seams)

- `AppAccents.byId` — fallback-to-forest for null/unknown ids (pure unit test).
- `AppUser` — `fromMap`/`toMap`/`toCreateMap` round-trip including new fields and `themeMode` string parsing, incl. legacy docs missing the new fields (defaults applied).
- `themeController` — reduce logic from `AppUser` → `{mode, seed}`, including logged-out default.
- `profile_controller` — orchestration with mocked `AuthRepository` + `CloudinaryUploader` + picker/compress (success, upload failure, persist failure, user-cancels-crop).
- Firestore rules self-update — verified manually (rules aren't unit-tested in this repo); negative case: a write touching `role`/`companyId` is rejected.

## 7. Risks & mitigations

- **Theme flash on cold start** before auth resolves → accept brand default until `currentUser` emits; no local cache added (keeps the flat-Firestore decision; revisit only if flash is objectionable).
- **`image_cropper` platform setup** → handled as an explicit implementation step with a build verification.
- **Scope size** ("all modules") → mitigated by strict sequencing; each phase is independently reviewable and shippable.
- **Rules regression** (locking out admins or users) → add the rule narrowly (owner-only, field-restricted) and verify both positive (self-update succeeds) and negative (role change rejected) paths before merge.

## 8. Out of scope

- Free-form color picker (presets only).
- Per-company branding/theming (user-level only).
- Localization / RTL work beyond what exists.
- Animated mascot (static Revvy assets reused).
