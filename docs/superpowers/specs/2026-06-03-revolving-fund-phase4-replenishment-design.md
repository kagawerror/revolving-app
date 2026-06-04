# Revolving Fund App — Phase 4 Design Spec (Replenishment + Low-Balance Alerts)

- **Date:** 2026-06-03
- **Status:** Approved (extends the Phases 1–3 spec)
- **Builds on:** `2026-06-03-revolving-fund-app-design.md` (§5 replenishment lifecycle)

## 1. Purpose

Close the imprest loop. When a fund's available balance falls to its low-balance threshold,
the incharge is alerted, compiles a **replenishment (liquidation) report** of all released-but-
not-yet-replenished requests, and submits it. An approver (superior/manager/CEO) approves it; on
approval the linked requests are tagged `replenished` and the fund balance is **reset to its
original ceiling** in one atomic transaction. Low-balance and replenishment events surface as
**in-app alerts** (FCM push is deferred to Phase 5).

## 2. Locked decisions (this phase)

| Decision | Choice |
|---|---|
| Activity during pending replenishment | **Block new releases** while a fund is `replenishing`; create/acknowledge still allowed |
| Single active replenishment per fund | Enforced — a fund may have at most one `draft`/`submitted` replenishment at a time |
| Low-balance alert surfacing | **Banner on incharge home** (derived from fund status) **+ an in-app alerts list** |
| Replenishment report content | **Auto-compiled** list of released-unreplenished requests + computed total + **optional** notes |
| Alert delivery | In-app only (a `notifications` collection); FCM push deferred to Phase 5 |
| Fund-balance-write rule hardening | Tighten the deferred `funds` update rule as part of this phase |

## 3. Replenishment lifecycle

```
DRAFT ──submit──> SUBMITTED ──approve──> APPROVED   (terminal)
                       │
                       └──reject──> REJECTED         (terminal)
```

- **Create (DRAFT):** Only allowed when the fund is **not already** `replenishing`. The system
  compiles every request for the fund with `status == released` and `replenishmentId == null`,
  computes the total, and creates a `draft` replenishment. The fund flips to `replenishing`
  (which blocks new releases). A fund with no released-unreplenished requests cannot start a
  replenishment.
- **Submit (DRAFT → SUBMITTED):** Incharge confirms (optional notes); approvers are alerted in-app.
- **Approve (SUBMITTED → APPROVED):** One atomic Firestore transaction:
  1. each `requestId` → `status: replenished`, `replenishmentId: <id>`;
  2. fund `availableBalanceCentavos` → `originalBudgetCentavos`;
  3. fund `status` → `active`;
  4. replenishment `status` → `approved`.
  The incharge is alerted in-app.
- **Reject (SUBMITTED → REJECTED):** Replenishment marked `rejected`; the linked requests are left
  untouched (still `released`, still pickable by a future report); the fund returns to `low` or
  `active` based on its current balance. The incharge is alerted in-app.
- **Discard draft:** An unsubmitted `draft` may be cancelled; the fund returns to `low`/`active`.

The single-active-replenishment-per-fund invariant (enforced via the `replenishing` status guard)
removes any risk of a released request being counted in two reports — no new releases occur while
replenishing, and only one replenishment can be open per fund.

## 4. Release interaction

The release transaction (Phase 3) gains one guard: if the fund's `status == replenishing`, the
release is rejected with a `ValidationFailure('Fund is being replenished; releases are paused.')`.
This is checked inside the existing `runTransaction` against the freshly-read fund.

## 5. Data model additions

```
replenishments/{replenishmentId}
  companyId, fundId, status,            # draft | submitted | approved | rejected
  requestIds[], totalCentavos,
  reportNotes,                          # optional, may be empty
  createdByUid, submittedByUid?, approvedByUid?,
  createdAt, submittedAt?, decidedAt?

notifications/{notifId}
  companyId, recipientRoles[],          # e.g. ['incharge'] or ['superior','manager','ceo']
  type,                                 # lowBalance | replenishmentSubmitted | replenishmentApproved | replenishmentRejected
  title, body,
  fundId?, replenishmentId?,
  readAt?, createdAt
```

- **Notifications are role-targeted** (array `recipientRoles`) within a company; a user's alert list
  is `notifications where companyId == myCompany AND recipientRoles array-contains myRole
  orderBy createdAt desc`. Unread badge = client-side count of `readAt == null`. Mark-read sets
  `readAt`.
- **Low-balance banner** is derived directly from the funds stream (`fund.status == low`) — no
  collection read required for the banner itself. A `lowBalance` notification is *also* written once
  when a release first drives the fund to `low`, so the event appears in the alerts list/history.

## 6. Security rules (additions + hardening)

- `replenishments`: read by `sameCompany`; create/update only by `isIncharge` for create/submit and
  by `isApprover` for the approve/reject transition (status-gated, like requests); no client deletes.
- `notifications`: read by `sameCompany` AND `myRole in recipientRoles`; create by any signed-in
  company member (events are written by the app during transactions); update limited to setting
  `readAt`; no deletes.
- **Funds hardening:** replace the open `allow update: if sameCompany(...)` with a rule that only
  permits balance/status writes by `isIncharge` (release/replenishment-create are incharge actions)
  OR `isApprover` (replenishment approval resets the balance). This closes the Phase-3 deferred hole.

## 7. New composite indexes

- `replenishments`: (`fundId` ASC, `status` ASC) — list active/ historical replenishments per fund.
- `notifications`: (`companyId` ASC, `recipientRoles` ARRAY, `createdAt` DESC) — the alerts list.

## 8. UI

- **Incharge home:** a low-balance **banner** when any company fund is `low`; per fund, a
  "Replenish" action (enabled when there are released-unreplenished requests and the fund isn't
  already replenishing) → a **replenishment review screen** (auto-compiled list + total + notes +
  Submit). A small **alerts** entry point (bell + unread badge) → alerts list.
- **Approver home:** a **pending replenishments** section alongside the pending requests, each opening
  a **replenishment detail screen** (fund, total, the itemized requests, notes) with Approve/Reject.
- **Alerts list screen:** shared, role-aware; tap marks read.

## 9. Out of scope (Phase 5+)

FCM push delivery, device-token registration, real-time monitoring dashboard, multi-fund report
batching, partial replenishment.
