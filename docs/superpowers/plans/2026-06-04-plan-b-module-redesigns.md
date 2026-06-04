# Plan B — Module Visual Redesigns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax. UI-composition tasks are executed via the `ui-designer` agent against the contracts below; logic-bearing widgets are TDD.

**Goal:** Redesign every module's screens to a bold, vibrant, world-class standard on top of the Plan A design system, weaving the Revvy mascot through empty/success moments — without changing any behavior, provider, or data contract.

**Architecture:** First complete the shared widget library in `lib/core/widgets/` (the spec named these; Plan A built only `AppAvatar`/`ProfileAvatarButton`). Then restyle each module's screens to consume those widgets + `AppTokens`/`AppAccents`/theme color roles. Pure-logic widgets (status→pill mapping) are TDD; screen restyles are contract-based and verified by `flutter analyze` clean + the full existing test suite staying green (121 tests) + no behavior change.

**Tech Stack:** Flutter 3.44.0, Riverpod, `flutter_animate`, `shimmer`, `cached_network_image`, existing theme system. `withValues`/`CardThemeData`/`surfaceContainerLow` available.

**Hard invariants (every task):**
- Do NOT change providers, repositories, domain models, routing logic, or Firestore reads/writes. Presentation only.
- Do NOT break existing tests. Run full `flutter test` after every group → 121+ pass.
- Respect dark mode: use `Theme.of(context).colorScheme` roles, never hardcoded `Colors.white`/`black` except for text/scrim over the seed gradient.
- `flutter analyze lib` adds NO new lints (7 pre-existing info-lints are the baseline).
- Reuse the Revvy mascot asset already used by `lib/features/welcome/presentation/welcome_screen.dart` (read it to find the asset path); do not add new mascot art.

---

## Group F — Shared widget library

Build the reusable widgets every module consumes. Logic-bearing ones are TDD; presentational ones are analyze-verified.

### Task F1: `StatusPill` (TDD — has mapping logic)

**Files:**
- Create: `lib/core/widgets/status_pill.dart`
- Test: `test/core/widgets/status_pill_test.dart`

- [ ] **Step 1: Read the status enums** — `lib/features/requests/domain/` (`RequestStatus`) and `lib/features/replenishment/domain/` (`ReplenishmentStatus`) for the exact enum values + any existing label/display getter. Reuse existing label getters if present.
- [ ] **Step 2: Write failing widget tests** — pump `StatusPill(label: 'Released', tone: StatusTone.success)` and assert the label text renders and the container uses the success color role. Assert a `StatusTone.danger`/`warning`/`neutral`/`info` each map to a distinct color from the scheme. (Write 3–4 assertions.)
- [ ] **Step 3: Implement** — a small `StatusPill` StatelessWidget taking `String label` + `StatusTone tone` (enum: neutral/info/success/warning/danger). Maps tone → `(background, foreground)` from `colorScheme` (e.g. success → tertiaryContainer/onTertiaryContainer or a green role; danger → errorContainer/onError­Container; warning → a derived amber; neutral → surfaceContainerHighest/onSurfaceVariant). Stadium shape (`AppTokens.rPill`), compact padding, `labelLarge` weight. Keep the tone→color map a pure static method so it's testable.
- [ ] **Step 4: Run tests** → pass.
- [ ] **Step 5: Commit** — `feat(widgets): StatusPill with tone-based color mapping`

### Task F2: presentational cards — `SurfaceCard`, `SectionHeader`, `AppListTile`

**Files:** Create `lib/core/widgets/surface_card.dart`, `section_header.dart`, `app_list_tile.dart`

- [ ] **Step 1: Implement `SurfaceCard`** — rounded (`AppTokens.brCard`) container over `colorScheme.surfaceContainerLow` with optional `AppTokens.softShadow`, `padding` param (default `EdgeInsets.all(AppTokens.lg)`), `child`, optional `onTap` (InkWell w/ matching radius).
- [ ] **Step 2: Implement `SectionHeader`** — `title` (titleMedium, w700) + optional `trailing` widget (e.g. a "See all" TextButton), consistent vertical rhythm using `AppTokens` spacing.
- [ ] **Step 3: Implement `AppListTile`** — themed row: optional leading (icon/avatar), title, subtitle, trailing; rounded, tappable, used across lists. Thin wrapper over `ListTile`/`InkWell` with the app's spacing + shapes.
- [ ] **Step 4: Verify** — `flutter analyze lib/core/widgets` → clean. Add a tiny smoke widget test that each renders a child without throwing (optional but cheap).
- [ ] **Step 5: Commit** — `feat(widgets): SurfaceCard, SectionHeader, AppListTile`

### Task F3: `BalanceHeroCard` + `StatCard`

**Files:** Create `lib/core/widgets/balance_hero_card.dart`, `stat_card.dart`

- [ ] **Step 1: `BalanceHeroCard`** — the gradient centerpiece: `AppTokens.heroGradient(seed)` background (seed from `themeControllerProvider` passed in or read by caller), a large primary amount (display weight, onPrimary/white text), a label, and an optional secondary row (e.g. "available / total"). Money formatting must reuse the app's existing `Money` formatter — read `lib/core/money/money.dart` for the format method; do NOT reformat centavos by hand.
- [ ] **Step 2: `StatCard`** — promote the private one from `dashboard_screen.dart`: `label`, `value` (String, already formatted by caller), optional `icon`, optional `tone` accent. Subtle `flutter_animate` fade/slide entrance. Fixed comfortable min size; wraps in grids.
- [ ] **Step 3: Verify** — analyze clean; values are passed pre-formatted (no money logic inside the widget).
- [ ] **Step 4: Commit** — `feat(widgets): BalanceHeroCard and StatCard`

### Task F4: `EmptyState`, `Skeleton`, `SuccessOverlay` (Revvy moments)

**Files:** Create `lib/core/widgets/empty_state.dart`, `skeleton.dart`, `success_overlay.dart`

- [ ] **Step 1: `EmptyState`** — centered Revvy mascot image (reuse welcome's asset), a title, a message, optional CTA button. Used for empty lists.
- [ ] **Step 2: `Skeleton`** — `shimmer`-based placeholder primitives: `Skeleton.box({width,height,radius})` and `Skeleton.line({width})`, plus a `SkeletonList` helper for N rows. Used as loading states.
- [ ] **Step 3: `SuccessOverlay`** — a celebratory transient overlay/dialog with Revvy + a message (e.g. "Released!"), auto-dismiss or tap-to-dismiss. Expose `SuccessOverlay.show(context, message)` static helper. Guard all post-await context use with `context.mounted`.
- [ ] **Step 4: Verify** — analyze clean; confirm the Revvy asset path resolves (it's already declared in `pubspec.yaml` assets since welcome uses it).
- [ ] **Step 5: Commit** — `feat(widgets): EmptyState, Skeleton, SuccessOverlay with Revvy`

---

## Group G — Dashboard redesign

**Files:** Modify `lib/features/dashboard/presentation/dashboard_screen.dart` (do NOT touch `dashboard_providers.dart`).

- [ ] **Step 1: Read** `dashboard_screen.dart` fully + `dashboard_providers.dart` to learn the exact data shape (summary fields, funds list, recent activity, loading/error/empty states already handled).
- [ ] **Step 2: Redesign (ui-designer)** against contracts:
  - Replace the top summary with a `BalanceHeroCard` (total/available balance) + an animated `StatCard` grid (disbursed, utilization %, fund count, pending counts) using `Wrap`/`GridView`.
  - Funds section: `SectionHeader` + `SurfaceCard` per fund with a styled `LinearProgressIndicator` (color by status via `StatusPill` tone), balance + threshold.
  - Recent activity: `SectionHeader` + a vertical timeline/list of `AppListTile`s with `StatusPill`s and `Money`-formatted amounts.
  - Loading → `Skeleton`/`SkeletonList`; empty → `EmptyState` (Revvy); error → existing error handling restyled.
  - Subtle staggered `flutter_animate` entrances. Keep all existing provider reads + the pending-count anti-flash behavior intact.
- [ ] **Step 3: Verify** — `flutter analyze lib` no new lints; `flutter test` 121+ pass (dashboard tests unchanged).
- [ ] **Step 4: Commit** — `feat(dashboard): bold dashboard redesign on the design system`

---

## Group H — Requests redesign

**Files:** Modify `incharge_home_screen.dart`, `approver_home_screen.dart`, `create_request_screen.dart`, `request_detail_screen.dart` (NOT the providers/controller).

- [ ] **Step 1: Read** all four screens + `request_providers.dart` + `create_request_controller.dart` + `RequestStatus` domain to preserve every behavior (release/ack/reject actions, image upload flow, status gating).
- [ ] **Step 2: Redesign (ui-designer)** against contracts:
  - **incharge_home**: funds as `SurfaceCard` sections; each request an `AppListTile` with `StatusPill` + context-aware action button (Mark ready / Release / status). Keep `LowBalanceBanner`, the AppBar actions (Dashboard, `AlertsBell`, the Plan A `ProfileAvatarButton`, Logout), and the "New request" FAB → `/incharge/create`.
  - **approver_home**: two `SectionHeader` sections (pending replenishments, pending requests) of `AppListTile`s → detail; `EmptyState` (Revvy) when empty.
  - **create_request**: a polished form in `SurfaceCard`s — fund dropdown, beneficiary, amount, purpose, and a prominent **image-upload card** (camera/gallery, preview, progress) reusing the EXISTING controller flow unchanged. Disable submit while uploading. On success consider a `SuccessOverlay`.
  - **request_detail**: hero proof image (`cached_network_image`, loading/error), details, a **status timeline**, and the approve/reject buttons gated exactly as today. Fix the 1 pre-existing `unnecessary_underscores` lint here while you're in the file.
  - Money via existing `Money` formatter; statuses via `StatusPill`.
- [ ] **Step 3: Verify** — analyze (the request_detail lint should now be gone → 6 baseline lints, none new); `flutter test` 121+ pass.
- [ ] **Step 4: Commit** — `feat(requests): redesign incharge/approver/create/detail screens`

---

## Group I — Replenishment redesign

**Files:** Modify `replenish_review_screen.dart`, `replenishment_detail_screen.dart` (NOT `replenishment_providers.dart`).

- [ ] **Step 1: Read** both screens + providers + `ReplenishmentStatus` domain to preserve the review/sign-off lifecycle and money math.
- [ ] **Step 2: Redesign (ui-designer)** — `SurfaceCard` layout, `StatusPill` for replenishment statuses, `Money`-formatted bundled totals, the list of released requests as `AppListTile`s, sign-off action buttons gated exactly as today. On successful sign-off → `SuccessOverlay` (Revvy). Empty/loading → `EmptyState`/`Skeleton`.
- [ ] **Step 3: Verify** — analyze no new lints; `flutter test` 121+ pass.
- [ ] **Step 4: Commit** — `feat(replenishment): redesign review + detail with sign-off success moment`

---

## Group J — Admin/Companies + Auth redesign

**Files:** Modify `admin_home_screen.dart`, `create_fund_screen.dart`, `login_screen.dart`, `bootstrap_screen.dart` (NOT controllers/providers).

- [ ] **Step 1: Read** the four screens + `admin_providers.dart` + `login_controller.dart` + `bootstrap_controller.dart` to preserve provisioning, validation, and auth flows.
- [ ] **Step 2: Redesign (ui-designer)**:
  - **admin_home**: `SurfaceCard` sections for companies/funds/users; `AppListTile`s; keep the `ProfileAvatarButton` entry point; `EmptyState` where lists are empty.
  - **create_fund**: form in `SurfaceCard`s, `Money` input handling unchanged, themed buttons.
  - **login**: a branded, bold/vibrant sign-in — gradient header or Revvy, themed fields/buttons, error mapping unchanged. Keep `--dart-define` secret-gating behavior.
  - **bootstrap**: matching first-run admin setup styling.
- [ ] **Step 3: Verify** — analyze no new lints; `flutter test` 121+ pass (login/bootstrap controller tests unchanged).
- [ ] **Step 4: Commit** — `feat(admin,auth): redesign admin/create-fund/login/bootstrap`

---

## Group K — Notifications + Welcome polish

**Files:** Modify `alerts_screen.dart`, `alerts_bell.dart`, `low_balance_banner.dart`, `welcome_screen.dart` (NOT `notification_providers.dart`).

- [ ] **Step 1: Read** the notification screens + providers + `welcome_screen.dart` to preserve the alerts stream, badge count, and welcome-gate timing.
- [ ] **Step 2: Redesign (ui-designer)**:
  - **alerts_screen**: `AppListTile`s with tone-colored leading icons + `StatusPill`s; `EmptyState` (Revvy) when no alerts; `Skeleton` while loading.
  - **alerts_bell**: refined badge styling consistent with the theme.
  - **low_balance_banner**: restyle as a prominent themed warning banner (warning tone).
  - **welcome_screen**: polish the existing Revvy splash to match the new bold/vibrant system (typography, gradient, motion) without changing the gate timing/behavior.
- [ ] **Step 3: Verify** — analyze no new lints; `flutter test` 121+ pass (welcome_gate test unchanged).
- [ ] **Step 4: Commit** — `feat(notifications,welcome): redesign alerts + polish welcome splash`

---

## Final verification

- [ ] Full `flutter test` → 121+ pass.
- [ ] `flutter analyze lib` → ≤6 baseline lints (request_detail one fixed), none new.
- [ ] Manual device pass (verify skill): each redesigned screen in light + dark + 2 accents; Revvy empty/success moments; no behavior regressions (create request, release, replenish sign-off, approve/reject still work).

---

## Self-Review

**Spec coverage (vs the design spec §4.2 widget library + §4.8 module list):** widget library → Group F (StatusPill, SurfaceCard, SectionHeader, AppListTile, BalanceHeroCard, StatCard, EmptyState, Skeleton, SuccessOverlay; AppAvatar/ProfileAvatarButton from Plan A). Dashboard → G. Requests → H. Replenishment → I. Admin/Companies + Auth → J. Notifications + Welcome → K. Revvy moments → F4 + woven into G/H/I/K. `AppScaffold` from the spec is intentionally dropped (YAGNI — per-screen AppBars already carry the avatar action; a wrapper adds indirection without payoff); noted here so it's a deliberate cut, not an omission.

**Placeholder scan:** UI tasks are contract-based (the correct form for design-iteration work, executed by ui-designer), each with concrete widget lists + verification commands. The one logic-bearing widget (StatusPill) is full TDD. No "handle edge cases" hand-waving.

**Type consistency:** `StatusTone` enum (F1) reused by dashboard/requests/replenishment/notifications. `SurfaceCard`/`SectionHeader`/`AppListTile`/`StatCard`/`BalanceHeroCard`/`EmptyState`/`Skeleton`/`SuccessOverlay` names consistent across G–K. Money always via the existing `Money` formatter (never hand-rolled). Statuses always via `StatusPill`.

**Risk:** the biggest is a screen restyle silently changing behavior (action gating, upload flow). Mitigated by the hard invariant "presentation only + full suite green after every group" and ui-designer being told to preserve every provider read and action condition.
