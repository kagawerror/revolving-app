# AGENTS.md — Development Guide for `rev_app`

This file orients **AI agents** (and humans) working in this repository. It complements
[`CLAUDE.md`](CLAUDE.md) — read that first for the authoritative architecture rules. This
document describes the **agent team** available for development and how they collaborate.

> TL;DR: A Flutter + Firebase (Spark tier, no Cloud Functions) app for managing company
> revolving / petty-cash funds. Feature-first + layered. Riverpod for state. Money is
> integer **centavos**. Repositories return `Result<T>`. Status changes are guarded state
> machines enforced **twice** (Dart + `firestore.rules`).

---

## 1. The Agent Team

Six specialist subagents live in [`.claude/agents/`](.claude/agents/). They are dispatched
via the Agent/Task tool, each in its own isolated context. One skill — **`team-lead`** —
orchestrates them end-to-end.

| Agent | Role | Use it when… |
|-------|------|--------------|
| **architect** | System planning & design | A feature needs a plan: data model, layering, state machine, indexes, rules. |
| **ui-designer** | World-class, user-friendly UI | Designing/refining screens, widgets, flows, accessibility, theming. |
| **coder** | Implementation (parallel for large tasks) | Turning a plan into Dart/Flutter code, TDD-first. |
| **reviewer** | Validation: SOLID, DRY, privacy, leaks | Verifying a change before it merges. |
| **debugger** | Root-cause bug fixing | A test fails, a crash repros, behavior is wrong. |
| **optimizer** | Performance: leaks, crashes, jank | Frame drops, high CPU/memory, slow startup, rebuild storms. |

### Orchestration: the `team-lead` skill

[`.claude/skills/team-lead/SKILL.md`](.claude/skills/team-lead/SKILL.md) drives a full
feature from idea to pushed commit, in this default order:

```
architect → ui-designer → coder → reviewer → optimizer → debugger → code-review-commit-push
```

Invoke it for any non-trivial feature. It chooses which stages apply, runs reviewer/debugger
in a loop until green, and finishes with a reviewed, committed, pushed change.

---

## 2. Project Map

```
lib/
  core/         money/ · error/ (Result<T>, Failure) · theme/ · config/
  services/     firebase · cloudinary · image · messaging
  features/<f>/ domain/ (pure Dart, models, repo interfaces, state machines)
                data/   (Firestore implementations)
                presentation/ (Riverpod providers + screens/controllers)
  routing/      app_router.dart (GoRouter, role-based redirect)
test/           mirrors lib/ — flutter_test + mocktail + fake_cloud_firestore
firestore.rules · firestore.indexes.json
```

Features: `auth`, `companies` (companies + funds), `requests`, `replenishment`,
`dashboard`, `notifications`, `messaging`.

Roles (`auth/domain/app_user.dart`): `admin`, `ceo`, `manager`, `superior`, `incharge`,
`employee`. `canApprove` = superior/manager/ceo; `canManageFund` = incharge; `isAdmin`.

---

## 3. Non-negotiable Conventions (agents MUST honor)

1. **Money = integer centavos.** Use `lib/core/money/money.dart`. Never `double` for amounts.
   Firestore stores `*Centavos` integer fields.
2. **Repositories return `Result<T>`** (`Ok`/`Err`), never throw. Catch, `developer.log` the
   real error, return a user-safe `Failure`. UI maps via `failure_ui.dart`.
3. **State machines enforced twice.** Update the Dart `_allowed` transition map **and** the
   matching block in `firestore.rules` together, or writes pass locally and fail on the server.
4. **Money mutations run in Firestore transactions** that re-read + re-validate against current
   server state. Push notifications happen **after** commit, `unawaited`, never affecting the txn.
5. **Multi-tenant by `companyId`.** Every doc carries it; rules scope with `sameCompany`.
   `companyId` + another filter ⇒ add a composite index to `firestore.indexes.json`.
6. **DI via Riverpod providers.** Never touch `FirebaseFirestore.instance` outside
   `firebase_providers.dart`. Inject + override in tests.
7. **TDD.** Extract pure decision functions (like `computeRelease`) from repositories and unit
   test them. Domain logic = pure tests; data = `FakeFirebaseFirestore`; presentation = overridden providers.

---

## 4. Commands

```sh
flutter pub get
flutter run --dart-define-from-file=.env     # secrets via String.fromEnvironment
flutter analyze                              # flutter_lints
flutter test                                 # all
flutter test test/core/money/money_test.dart # single file
flutter test --name "computeRelease"         # by name
firebase deploy --only firestore             # rules + indexes
```

The app **must** be launched with `--dart-define-from-file=.env` (Cloudinary/OneSignal config).
Features guard on `AppSecrets.hasCloudinary` / `hasPushRelay`.

---

## 5. Working Agreement for Agents

- **Verify before claiming done.** Run `flutter analyze` and the relevant `flutter test`.
  Quote real output — never assert success without evidence.
- **Stay in your lane, then hand off.** Each subagent returns a tight summary (what changed,
  files touched, what to check next) so the `team-lead` can route the next stage.
- **Privacy first.** Proof photos, user emails, and fund amounts are sensitive. Never log raw
  PII; never widen Firestore rules without re-checking `sameCompany` scoping.
- **Small, reversible steps.** Match surrounding code style. Prefer extracting a testable pure
  function over fattening a repository.
