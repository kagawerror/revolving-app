# Revolving Fund App — Design Spec

- **Date:** 2026-06-03
- **Status:** Approved (design); implementation plan pending
- **Stack:** Flutter (Android + iOS), Firebase (Auth, Firestore, Cloud Messaging), Cloudinary (image proof), Riverpod + Repository pattern

## 1. Purpose

A multi-company **revolving fund** (imprest / petty-cash) management app. Each company maintains
one or more revolving funds with a fixed budget ceiling. An **Incharge** raises spending requests
against a fund on behalf of employees; an **approver** (Superior / Manager / CEO) acknowledges them;
approved requests are released, drawing down the fund balance. When the balance falls to a
configurable low-balance threshold (default 3% of the ceiling), the Incharge compiles a
**replenishment (liquidation) report**, a superior approves it, and the fund resets to its original
ceiling. A real-time dashboard monitors balances and activity. Every state change is recorded as an
append-only audit trail.

## 2. Roles

| Role | Capabilities |
|---|---|
| **Admin** | Provisions users (admin-provisioned onboarding — no open signup), creates companies & funds, assigns roles and company membership. |
| **Incharge** (fund custodian) | Creates requests (recording the beneficiary employee), attaches required proof image, sends for acknowledgement, marks acknowledged requests Ready for Release / Released, receives low-balance alerts, compiles and submits replenishment reports. |
| **Employee** (beneficiary) | The person a request's funds are for. Recorded on the request. |
| **Superior / Manager / CEO** (approver) | Acknowledges (approves/rejects) requests and replenishment reports. **Single approver:** any one assigned approver of that company can approve. |

**Confirmed interpretation:** The **Incharge creates the request** in the system and records which
**employee** it is for. A request therefore carries both `createdByUid` (incharge) and
`beneficiaryName`/beneficiary reference. Employees do not draft their own requests in v1.

## 3. Architecture

Clean layered architecture organized **by feature**, with one-way dependencies
(presentation → domain ← data). Riverpod provides DI and state; `go_router` provides role-guarded
navigation.

```
lib/
  core/              # Result/error types, Money value object, constants, theme, shared DI
  services/          # Firebase init, Cloudinary uploader, FCM, image picker/compressor
  features/
    auth/            # login, session, role gating
    companies/       # company + fund records and admin provisioning
    requests/        # request lifecycle (core)
    replenishment/   # liquidation/imprest report cycle
    dashboard/       # real-time monitoring
    notifications/   # FCM + in-app inbox
  routing/           # go_router with role-based guards
```

Each feature has three layers:

- **data** — `FirestoreXRepository implements XRepository`; all Firestore/Cloudinary specifics live here.
- **domain** — immutable models, `XRepository` *interfaces*, and pure use-cases (business rules, no
  Flutter/Firebase imports → unit-testable in isolation).
- **presentation** — Riverpod providers + screens/widgets.

The SOLID dependency-inversion boundary is the **repository interface**: domain depends on the
abstraction; data implements it. The imprest math and approval/transition rules live in the domain
layer and are unit-tested without Firebase.

### Key correctness decisions

- **Money value object** wrapping `int` centavos with `+`/`-`/percentage operators. Amounts are
  **never** stored or computed as `double`. Firestore stores integer `*Centavos` fields.
- **State machines, not boolean flags.** Request status and replenishment status are enums with an
  explicit allowed-transition table; illegal transitions throw. This is what makes the audit trail
  trustworthy.

## 4. Firestore Data Model

Multi-company isolation via a `companyId` on every document, enforced by security rules.

```
companies/{companyId}
  name, createdAt

funds/{fundId}
  companyId, name, originalBudgetCentavos,
  availableBalanceCentavos, lowBalanceThresholdPct (default 3),
  status: active | low | replenishing

users/{uid}
  companyId, role, displayName, email, fcmTokens[]

requests/{requestId}
  companyId, fundId, createdByUid, beneficiaryName,
  amountCentavos, purpose, proofImageUrl (Cloudinary),
  status, replenishmentId?, timestamps, approverUid?, approverDecisionAt?
  history/{eventId}        # append-only audit subcollection

replenishments/{replenishmentId}
  companyId, fundId, status, requestIds[],
  totalCentavos, reportNotes, submittedByUid, approvedByUid, timestamps

notifications/{notifId}
  companyId, recipientUid, type, payload, readAt?
```

Balance mutations (deduct on release, reset on replenish) run inside **Firestore transactions** so
concurrent releases cannot corrupt the balance.

## 5. Core Workflows

### Request lifecycle

```
DRAFT → PENDING_ACK → ACKNOWLEDGED → READY_FOR_RELEASE → RELEASED → REPLENISHED
                ↓
            REJECTED
```

- `DRAFT → PENDING_ACK`: Incharge sends. **A proof image is required** to leave DRAFT (enforced in
  domain + security rules). Notifies approvers.
- `→ ACKNOWLEDGED`: an approver approves. Notifies incharge. (`→ REJECTED` on rejection.)
- `→ READY_FOR_RELEASE → RELEASED`: Incharge releases. RELEASED runs a transaction that **deducts**
  `amountCentavos` from the fund's `availableBalanceCentavos`. If the new balance ≤
  `originalBudgetCentavos * lowBalanceThresholdPct/100`, the fund flips to `low` and the incharge is
  alerted.
- `→ REPLENISHED`: applied in bulk when a replenishment report is approved.

### Replenishment (imprest) lifecycle

```
DRAFT → SUBMITTED → APPROVED
              ↓
          REJECTED  (back to incharge)
```

- Incharge compiles all `RELEASED`-but-not-yet-`REPLENISHED` requests for the fund into a report →
  `SUBMITTED` → notifies superior.
- Superior `APPROVED` → transaction: tag those requests `REPLENISHED`, **reset
  `availableBalanceCentavos` to `originalBudgetCentavos`**, fund returns to `active`, notify incharge.

## 6. Security & Secrets

- **Firestore Security Rules are the enforcement layer** (client-side role checks are UX only):
  - A user may read/write only documents where `companyId` equals their own.
  - Only approver roles may transition a request to `ACKNOWLEDGED`/`REJECTED`.
  - Only the incharge role may release requests and submit replenishments.
  - Balance fields are writable only via the allowed transitions.
  - `requests` cannot leave `DRAFT` without a non-empty `proofImageUrl`.
- **Cloudinary** uploads use an **unsigned upload preset** scoped to a folder; the API secret never
  ships in the app. Only the resulting secure URL is stored in Firestore.
- **No secrets in git:** `google-services.json`, Cloudinary cloud name + unsigned preset, and any
  keys are supplied via `--dart-define` / a gitignored config file. A `config.example` documents the
  required keys.
- The append-only `history` subcollection provides a tamper-evident audit trail.

## 7. Delivery Phases

Each phase is independently shippable and verified (with domain unit tests) before the next.

1. **Foundation** — fix the Gradle `google-services` plugin bug in
   `android/app/build.gradle.kts` (Groovy syntax in a Kotlin DSL file), add Firebase / Riverpod /
   go_router dependencies, FlutterFire init, `core/` (Money, Result, errors, theme), DI.
2. **Auth + multi-tenancy** — login, role-gated routing, admin provisioning of users / companies / funds.
3. **Requests** — create (with Cloudinary proof upload), acknowledge, release + balance deduction. Core of the app.
4. **Replenishment + low-balance alerts** — imprest cycle, report submit/approve, threshold alerting.
5. **Notifications** — FCM + in-app inbox wired to workflow events.
6. **Real-time dashboard** — live fund balances, pending counts, recent transactions via Firestore streams.

## 8. Decisions Log (from brainstorming)

| Decision | Choice |
|---|---|
| Platforms / dashboard | Mobile-only (Android + iOS); dashboard is an in-app screen |
| Approval model | Single approver — any assigned superior/manager/CEO |
| State management / architecture | Riverpod + Repository pattern, clean layers |
| User onboarding | Admin-provisioned (no open signup) |
| Replenishment model | Imprest cycle — reset balance to original ceiling on approval |
| Low-balance threshold | Configurable per company/fund, default 3% |
| Notifications | FCM push + in-app inbox |
| Image proof storage | Cloudinary external free tier; store URL only |

## 9. Out of Scope (v1 / YAGNI)

- Open self-signup, password-reset flows beyond Firebase defaults.
- Multi-currency (single currency, centavo minor units).
- Amount-threshold or sequential approval chains (single-approver only).
- Employees drafting their own requests.
- Web/desktop dashboard build.
