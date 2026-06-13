# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`rev_app` ("Revolving Fund") is a Flutter app for managing company petty-cash / revolving funds: an **incharge** custodian creates spending requests (with a proof photo), **approvers** (superior/manager/ceo) acknowledge or reject them, the incharge releases cash (deducting the fund balance), and later bundles released requests into a **replenishment** report that an approver signs off to reset the balance. **Admins** provision companies, funds, and users. Backend is Firebase (Auth + Firestore) on the **free Spark tier — no Cloud Functions**; push goes through OneSignal + a separate Cloudflare Worker relay.

## Commands

```sh
flutter pub get                              # install deps
flutter run --dart-define-from-file=.env     # run (env carries Cloudinary/OneSignal config)
flutter analyze                              # lint (flutter_lints, build/** excluded)
flutter test                                 # all tests
flutter test test/core/money/money_test.dart # single file
flutter test --name "computeRelease"         # single test by name
firebase deploy --only firestore             # deploy firestore.rules + firestore.indexes.json
```

The app reads all secrets via `String.fromEnvironment` (see `lib/core/config/app_secrets.dart`), so it **must** be launched with `--dart-define-from-file=.env`. Without it, Cloudinary uploads and push are disabled (guarded by `AppSecrets.hasCloudinary` / `hasPushRelay`). See `SETUP.md` for first-time Firebase/Cloudinary/OneSignal setup and admin seeding; `relay/README.md` for the Worker (deployed separately with `wrangler`, not part of the Flutter build).

## Architecture

**Feature-first + layered.** `lib/features/<feature>/` each contain three layers with the dependency arrow pointing inward:
- `domain/` — pure Dart: immutable `Equatable` models, repository *interfaces*, status state machines. No Firebase imports except `FieldValue`/`Timestamp` in model `fromMap`/`toCreateMap`.
- `data/` — Firestore implementations of the domain repository interfaces.
- `presentation/` — Riverpod providers + screens/controllers.

Features: `auth`, `companies` (companies + funds), `requests`, `replenishment`, `dashboard`, `notifications`, `messaging` (push). Cross-cutting code lives in `lib/core/` (money, error, theme, config) and `lib/services/` (firebase, cloudinary, image, messaging). Routing is in `lib/routing/app_router.dart`.

**State management = Riverpod.** DI is provider-based: `firebase_providers.dart` exposes `firebaseAuthProvider` / `firestoreProvider`; each feature's `*_providers.dart` wires repositories on top of them. To make code testable, inject dependencies through providers and override them in tests — never reach for `FirebaseFirestore.instance` directly outside `firebase_providers.dart`.

**Routing = GoRouter with role-based redirect.** `routerProvider` bridges the `currentUserProvider` auth stream to a `Listenable` and redirects by role via `homeFor(UserRole)` (`/admin`, `/incharge`, `/approvals`). It returns `null` (no redirect) while auth is loading to avoid flicker. Add new screens as `GoRoute`s here.

## Conventions that are easy to get wrong

**Money is integer centavos — never `double`.** Use `lib/core/money/money.dart` (`Money`) for all amounts. `Money.fromCentavos` is authoritative; `Money.fromPesos` routes through `double` and is for human/UI input only. Firestore stores `*Centavos` integer fields (e.g. `amountCentavos`, `availableBalanceCentavos`).

**Status changes are guarded state machines, enforced twice.** `RequestStatus` and `ReplenishmentStatus` (in their `domain/`) own an `_allowed` transition map with `canTransitionTo`. The *same* legal transitions are independently re-encoded in `firestore.rules`. When you change a lifecycle, update **both** the Dart state machine and the matching rule block, or writes will pass locally and be rejected by Firestore (or vice-versa).

**Repositories return `Result<T>`, not exceptions.** `lib/core/error/` defines a sealed `Result<T>` (`Ok`/`Err`) and a sealed `Failure` hierarchy (`AuthFailure`, `PermissionFailure`, `ValidationFailure`, `NotFoundFailure`, `UnexpectedFailure`). Data-layer methods catch, `developer.log` the real error, and return a user-safe `Err(...)`. UI maps failures via `lib/core/error/failure_ui.dart`. Don't let raw exceptions escape repositories.

**Money mutations run in Firestore transactions and re-validate inside.** See `FirestoreRequestRepository.release` / `transition`: they re-read the doc inside `runTransaction` and re-check the transition against the *current* server state (concurrent-edit guard) before writing. Release also writes an audit entry to the request's `history` subcollection. Side effects that aren't money (push notifications) happen **after** commit, are `unawaited`, and never affect the transaction result. Pull purely-computational decisions out as testable free functions (e.g. `computeRelease(Fund, Money) -> ReleaseOutcome`).

**Multi-tenant isolation by `companyId`.** Nearly every document carries `companyId`; Firestore rules scope reads/writes to the caller's own company (`sameCompany`). Queries that filter by `companyId` + another field need a composite index in `firestore.indexes.json`.

## Roles

`UserRole` (auth/domain/app_user.dart): `admin`, `ceo`, `manager`, `superior`, `incharge`, `employee`. Helpers: `canApprove` (superior/manager/ceo — single-approver model), `canManageFund` (incharge only — creates/releases/replenishes), `isAdmin`. Role drives both the router landing page and Firestore-rule permissions.

## Testing

`flutter_test` + `mocktail` (mock repos) + `fake_cloud_firestore` (in-memory Firestore for data-layer tests). Tests mirror `lib/` under `test/`. Pattern: domain logic is tested as pure functions/models; data repositories against `FakeFirebaseFirestore`; presentation controllers with overridden providers. New features follow TDD here — pure decision functions extracted from repositories (like `computeRelease`) are the unit-test seam.
