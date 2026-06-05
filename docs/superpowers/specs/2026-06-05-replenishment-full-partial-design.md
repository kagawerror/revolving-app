# Full / Partial replenishment — Design

**Date:** 2026-06-05
**Branch:** `feat/plan-b-module-redesigns`
**Status:** Approved (design), pending implementation plan
**Builds on:** `2026-06-05-replenishment-multiselect-popup-design.md` (the multi-select popup + `createAndSubmit` + incremental `approve` this revises)

## Problem

The just-shipped replenishment popup treats every selected released request as an all-or-nothing **full** replenishment. The user wants per-request control: for each released request in the popup, choose **Full** or **Partial**. Partial means "credit the fund part of what this request owes back, but keep the request open until the rest is replenished" — an installment model.

## Decisions (from brainstorming)

- **Granularity:** the Full/Partial choice is **per request, inside the popup**. One report can mix full and partial rows.
- **Partial money:** on approval, the partial amount is **added to the fund**; the request's outstanding shrinks; its status **stays `released`**.
- **Approval:** both full and partial ride in the **same replenishment report → approver approves**; nothing moves until approval.
- **Installments:** a released request may receive **several partials over time**; when a Full is chosen on the remainder it becomes `replenished`.
- **Partial is strictly less than remaining:** a partial amount must satisfy `0 < amount < remaining`. To close a request, choose Full. This avoids a "released with zero outstanding" limbo. (User confirmed.)
- **Partial requires remarks** (non-empty).

## Data model changes

### `FundRequest` (`lib/features/requests/domain/fund_request.dart`)
- New field `replenishedCentavos` (int, default `0`; legacy docs → `0`).
- New getter `Money get replenished => Money.fromCentavos(replenishedCentavos);`
- New getter `Money get remaining => amount - replenished;`
- `amount` is unchanged and immutable — it is the original released amount (what was deducted from the fund).
- `toCreateMap()` writes `replenishedCentavos: 0`.
- The incharge monitoring list (`incharge_home_body.dart`) shows `remaining` as the request's amount, with a quiet "`{replenished} of {amount} replenished`" hint when `replenishedCentavos > 0`. Other screens that show the original `amount` are unchanged.

### `Replenishment` (`lib/features/replenishment/domain/replenishment.dart`)
- New field `items: List<ReplenishmentItem>`.
- New value type `ReplenishmentItem` (in the same file or a sibling `replenishment_item.dart`):
  `{String requestId, bool isPartial, Money amount, String remarks}` — `Equatable`, with `fromMap`/`toMap`.
- `total` = sum of `items[].amount` (unchanged meaning: the amount credited to the fund on approval).
- `requestIds` is retained and derived as `items.map((i) => i.requestId)` for the existing detail screen and backward-compat.
- `fromMap`: if the doc has no `items` array (legacy), synthesize one Full item per `requestId` using the stored `totalCentavos` split is NOT possible per-request, so legacy items get `amount = 0`/`isPartial = false`; legacy reports are display-only history and never re-approved, so this is acceptable. (The detail screen reads `requestIds`/`total`, not per-item amounts, for legacy docs.)
- `toCreateMap()` (or the inline `tx.set` map) writes `items` as a list of maps plus the derived `requestIds` and `totalCentavos`.

### New collection `partialReplenishments` (top-level, company-scoped)
Fields: `{companyId, fundId, requestId, replenishmentId, amountCentavos, remarks, createdByUid, approvedByUid, createdAt}`.
- Created **one per approved partial item**, inside the `approve` transaction.
- Provides the partial-history audit trail per request.
- A new `partial_replenishment.dart` domain model (`Equatable`, `fromMap`/`toCreateMap`) plus repository read method `watchByRequest(companyId, requestId)` for any future per-request history view (the write happens inside the replenishment repo's `approve` transaction, so no separate write method is strictly required, but the model is shared).

## Repository changes (`firestore_replenishment_repository.dart`)

### `createDraft` / `createAndSubmit` take items, not just ids
- New signature: `createDraft({required String fundId, required List<ReplenishmentItem> items, required String createdByUid})` and the matching `createAndSubmit({required String fundId, required List<ReplenishmentItem> items, required String actorUid, required String notes})`.
- Validation (company-scoped query as today — the permission-denied fix stays):
  - `items` non-empty; dedup by `requestId` (a request appears at most once per report).
  - Every `requestId` is in the releasable set (`status == released` and `remaining > 0`).
  - For a **Full** item: server recomputes `amount = remaining` (ignore any client amount); remarks ignored/empty.
  - For a **Partial** item: `0 < amount < remaining` (using server `remaining`) else `ValidationFailure`; `remarks` non-empty else `ValidationFailure`.
  - `total = sum(items[].amount)`.
  - Write-count guard: cap items so the approve transaction stays under Firestore's 500-write limit. Each partial item = 2 writes (partial-record create + request update); each full item = 1 write; plus fund + replenishment = 2. Cap items at **200** (well under 500 even if all partial) with a `ValidationFailure` over the cap.
- The transaction is otherwise as today: re-read the fund, reject if `replenishing`, create the draft with `items`, lock the fund to `replenishing`.

### `approve` applies items (one transaction)
Inside the existing transaction, after the rep-status and fund re-reads:
- Fund: `availableBalanceCentavos = (fund.availableBalance + replenishment.total).centavos`, status via `_restoredStatus` on the new balance (unchanged from current incremental approve).
- For each `item` in `replenishment.items`:
  - **Full** (`!item.isPartial`): `tx.update(request, {status: replenished, replenishmentId: repId, replenishedCentavos: FieldValue.increment(item.amount.centavos)})`.
  - **Partial** (`item.isPartial`): `tx.set(partialReplenishments.doc(), {companyId, fundId, requestId, replenishmentId: repId, amountCentavos: item.amount.centavos, remarks: item.remarks, createdByUid: replenishment.createdByUid, approvedByUid: actorUid, createdAt: serverTimestamp})` AND `tx.update(request, {replenishedCentavos: FieldValue.increment(item.amount.centavos)})` (status untouched, no `replenishmentId`).
- `FieldValue.increment` is safe here because the fund lock guarantees no concurrent report touches the same request between draft and approval, so the stored item amounts remain valid.
- `reject` / `discardDraft` unchanged (no items applied; fund just unlocks).

## Twice-enforced lifecycle change

### Dart state machine (`request_status.dart`)
Unchanged. `released → replenished` remains the only **status** transition. A partial is a same-status field update (`replenishedCentavos` only), which the enum graph does not govern.

### `firestore.rules` (MUST be edited AND deployed)
- **`requests` update** — add an approver/admin branch for a partial:
  - `resource.data.status == 'released'` and `request.resource.data.status == 'released'`
  - `request.resource.data.replenishedCentavos > resource.data.replenishedCentavos` (strictly increases)
  - `request.resource.data.amountCentavos == resource.data.amountCentavos` (original amount immutable)
  - guarded by `(isApprover() || isAdmin())` and `(sameCompany(...) || isAdmin())`.
  - The existing `released → replenished` (full) branch stays; it may also set `replenishedCentavos` (no tightening required).
- **new `match /partialReplenishments/{id}`**:
  - `allow read: if isAdmin() || sameCompany(resource.data.companyId);`
  - `allow create: if (isApprover() || isAdmin()) && (sameCompany(request.resource.data.companyId) || isAdmin());`
  - `allow update, delete: if false;`
- **`Replenishment` create/update** rules: unchanged (status-based; `items` is just extra payload). No index changes (no new query shape; `partialReplenishments` `watchByRequest` is `companyId == && requestId ==`, equality-only, no composite index).

## Presentation changes

### `ReplenishSelectDialog` (`replenish_select_dialog.dart`)
- Each releasable request row: a checkbox; when checked, a **Full | Partial** segmented control (default **Full**).
- When **Partial** is selected for a row: reveal an **amount** `TextField` (peso input, validated to `0 < x < remaining`) and a **remarks** `TextField` (required).
- The row's contribution to the running **selected total**: Full → `remaining`; Partial → entered amount (0 if blank/invalid).
- "Submit for approval" is enabled only when ≥ 1 row is selected and every selected row is valid (Full always valid; Partial needs a valid amount and non-empty remarks).
- On submit: build `List<ReplenishmentItem>` and call `createAndSubmit`. Pop `true` on success (caller shows the success overlay) — unchanged contract.
- Empty state unchanged.

### Incharge monitoring (`incharge_home_body.dart`)
- The per-fund request list shows `request.remaining.format()` as the amount for `released` requests, with a `replenishedCentavos > 0` hint line. The releasable filter for the popup becomes `status == released && remaining > 0` (was `status == released && replenishmentId == null`).

## Tests

- **Model:** `FundRequest.remaining`/`replenished` math; `fromMap` defaults `replenishedCentavos` to 0; `ReplenishmentItem` round-trips; `Replenishment.total` = sum of items; legacy `fromMap` (no `items`) yields Full items / preserves `requestIds`.
- **Repo `createDraft`:** builds mixed full/partial items; Full item amount = server `remaining` (client amount ignored); Partial rejected when `amount >= remaining`, `amount <= 0`, or remarks empty; dedup; >200 cap.
- **Repo `approve`:** fund credited by `total`; a Full item → request `replenished` + `replenishedCentavos == amount` + `replenishmentId` set; a Partial item → request stays `released`, `replenishedCentavos` bumped, a `partialReplenishments` doc created with the remarks; a mixed report does both atomically.
- **Installments:** release a request, approve a partial (stays released, remaining shrinks), approve a second partial, then a Full on the remainder → `replenished`; fund fully restored; two `partialReplenishments` records exist.
- **Dialog:** per-row Full/Partial toggle; submit disabled until selected rows valid; Partial requires amount `< remaining` and remarks; running total reflects full-remaining + partial amounts.
- **Dashboard fake repo:** updated to the new `createDraft`/`createAndSubmit` item signatures.

## Out of scope / unchanged

- `RequestStatus` status graph; `reject`/`discardDraft` logic; the approver approval UI (it approves the whole report as today); the fund-lock-while-replenishing behavior.
- No new composite indexes.

## Obligations

1. **Deploy `firestore.rules`** after implementation (`firebase deploy --only firestore`). This change adds a collection and a request-update branch; it will be rejected on device until deployed. (Recurring project gotcha: local rule edits don't take effect until deployed.)
2. **Revert desktop plugin-registrant churn** (`linux/`, `windows/`, `macos/Flutter/GeneratedPluginRegistrant.swift`) before committing, per project convention.

## Migration / backward compatibility

Zero migration. New requests get `replenishedCentavos: 0`; legacy requests read as `0`. New reports carry `items`; legacy reports (no `items`) read as Full items and remain display-only history. Existing fully-released → fully-replenished flow is unchanged when every row is left on the Full default.
