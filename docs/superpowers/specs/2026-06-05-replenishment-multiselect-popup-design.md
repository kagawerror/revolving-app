# Replenishment multi-select popup — Design

**Date:** 2026-06-05
**Branch:** `feat/plan-b-module-redesigns`
**Status:** Approved (design), pending implementation plan

## Problem

Two issues with the incharge "Replenish" action on a fund:

1. **It fails on device with `permission-denied`.** Tapping Replenish calls
   `FirestoreReplenishmentRepository.createDraft`, which queries released
   requests filtered by `fundId` + `status` only — with **no `companyId`
   filter**. The Firestore read rule is `sameCompany(resource.data.companyId)`,
   and Firestore rejects any query it cannot prove stays inside the caller's
   company. (Tests pass because `fake_cloud_firestore` ignores rules.)

2. **There is no selection step.** `createDraft` auto-bundles *all* released
   requests into one all-or-nothing report. The incharge cannot choose a subset.

We want: tapping Replenish opens a popup listing the released-but-not-yet-
replenished requests, the incharge checks the ones to include, and submitting
sends a replenishment report for approval. On approval, the selected amounts
return to the fund balance.

## Decisions (from brainstorming)

- **Approval model:** incharge **selects** a subset → submits a report → an
  **approver signs off** → only then does the money return. (Keeps today's
  audit/approval gate; adds subset selection.)
- **Refund math:** **add back each selected amount** (the exact inverse of the
  release that deducted it), *not* reset-to-original-budget. Reset-to-original
  over-refunds on a partial selection.
- **Popup flow:** the popup **confirms & submits directly** — selection +
  optional notes + one "Submit for approval" button. No intermediate review
  screen.
- **Default selection:** **nothing pre-checked**; the incharge deliberately
  checks each request to include.

## Key property: no Firestore rule changes

The chosen model needs **no changes to `firestore.rules`**:

- The fund-update rule already lets an incharge *or* an approver write any fund
  field, including the balance (it trusts the in-repo transaction to
  re-validate). So the incremental-refund arithmetic is invisible to the rules.
- `released → replenished` is already an approver-only request transition.
- `draft → submitted` (incharge) and `submitted → approved` (approver) already
  exist.

State machines (`ReplenishmentStatus`, `RequestStatus`) and
`firestore.indexes.json` are likewise unchanged.

## Changes

### 1. `createDraft` — fix the denial + accept a selection

`FirestoreReplenishmentRepository.createDraft`
(`lib/features/replenishment/data/firestore_replenishment_repository.dart`):

- New signature accepts an explicit selection:
  `createDraft({required String fundId, required List<String> requestIds, required String createdByUid})`.
- Read the fund first to obtain `companyId`, then query released requests
  **company-scoped** (`companyId` + `fundId` + `status == released`) — this is
  the permission-denial fix.
- Filter the query result to the requested `requestIds` that are still
  released-and-unreplenished (`replenishmentId == null`). Validate the
  resulting set is **non-empty** and a subset of the releasable set; reject
  with `ValidationFailure` otherwise. Keep the existing `> 450` batch guard.
- Compute `total` from the *selected* requests only.
- Transaction is otherwise unchanged: re-read the fund, reject if it is already
  `replenishing`, create the `draft` with the selected `requestIds`/`total`,
  lock the fund to `replenishing`.

### 2. New `createAndSubmit` — one-tap selection→submit

Because the replenishment **create** rule requires `status == 'draft'`, a doc
cannot be created already-submitted. So a one-tap submit composes two writes:

`createAndSubmit({required String fundId, required List<String> requestIds, required String actorUid, required String notes}) -> Result<void>`

- Calls `createDraft(...)`; on success calls `submit(...)`.
- **If `submit` fails, discard the draft** (`discardDraft`) so the fund is not
  left orphaned in `replenishing`. Return the original failure.
- Returns `Ok(null)` once submitted.

### 3. `approve` — incremental refund + balance-derived status

`FirestoreReplenishmentRepository.approve` (inside the existing transaction):

- Change the fund write from
  `availableBalanceCentavos = fund.originalBudget.centavos` (reset) to
  `availableBalanceCentavos = (fund.availableBalance + replenishment.total).centavos`
  (add back exactly what was released for the bundled requests).
- Set fund `status` **derived from the new balance** (`low` if the new balance
  is at/under the low threshold, else `active`) instead of hard-coded `active`.
  Reuse the same balance→status logic as `_restoredStatus`, applied to the new
  balance.
- Requests still transition `released → replenished` with the `replenishmentId`
  stamp (unchanged).

The new balance is mathematically bounded by the original budget (each released
request is replenished at most once — it leaves the `released` set via its
`replenishmentId` stamp — so the sum added back across all replenishments never
exceeds the sum deducted at release). No explicit cap is applied.

### 4. New dialog `ReplenishSelectDialog`

New widget under `lib/features/replenishment/presentation/`:

- Input: the `Fund` and the list of its released-unreplenished `FundRequest`s.
  The list is filtered in-memory from the already-loaded, already
  company-scoped `_fundRequestsProvider` in `incharge_home_body.dart`
  (`status == released && replenishmentId == null`) — **no new query/provider**.
- A checkbox per row showing beneficiary · purpose · amount; **none checked
  initially**.
- A live **selected-total** footer and an optional **notes** `TextField`.
- One **"Submit for approval"** button, disabled until ≥ 1 request is selected
  and while busy.
- On tap: `createAndSubmit(fundId, selectedIds, actorUid, notes)`. On success,
  close the dialog and show the `SuccessOverlay` ("Submitted for approval");
  on failure, surface via `showFailure` and keep the dialog open.
- **Empty state** when there are no releasable requests.

### 5. Wiring

- `_replenish` in `incharge_home_body.dart` opens `ReplenishSelectDialog`
  instead of calling `_startReplenish`.
- Remove the now-dead `_startReplenish` helper and the
  `ReplenishReviewScreen` (and its now-unused imports), since `createDraft` no
  longer auto-bundles into that read-only review path.

### 6. Tests

- `createDraft`: rejects an empty selection; rejects ids outside the
  releasable set; sums `total` from only the selected requests; the
  company-scoped query path is exercised.
- `createAndSubmit`: discards the draft (fund unlocked) when `submit` fails;
  leaves a `submitted` report + locked fund on success.
- `approve`: adds back `total` to the existing balance (not reset); a partial
  replenishment that leaves the balance under threshold yields `low` status; a
  full replenishment yields `active`.
- Dialog controller / widget: selection toggles update the running total;
  the submit button enables only with ≥ 1 selected; empty state renders when
  nothing is releasable.

## Out of scope / unchanged

- `firestore.rules` and `firestore.indexes.json`.
- `ReplenishmentStatus` / `RequestStatus` state machines.
- The approver-side approval/rejection UI and `reject` / `discardDraft` logic
  (beyond `createAndSubmit` reusing `discardDraft` for cleanup).

## Behavioral note (improvement)

Today, tapping Replenish immediately locks the fund to `replenishing` even if
the incharge backs out, and there is no resume UI for an orphaned draft. With
the dialog, the fund is locked only when the incharge actually submits — a
strict improvement that sidesteps the existing orphaned-draft gap.
