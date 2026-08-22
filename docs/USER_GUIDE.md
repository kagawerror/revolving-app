# Revolving Fund App — What It Is & How It Works

## What this app is for

The **Revolving Fund app** helps companies manage their **petty cash / revolving funds** in one place. Instead of paper forms, photos of receipts in a group chat, and manual balance tracking, the app gives every fund a single source of truth: who spent what, who approved it, how much cash is left, and when the fund was topped back up.

It replaces the usual mess of:
- Custodians keeping a notebook of expenses
- Chasing managers for approval over chat
- Guessing the remaining balance
- Reconciling receipts at the end of the month

---

## Who uses it (Roles)

| Role | What they do |
|------|--------------|
| **Incharge** (custodian) | Holds the cash. Creates spending requests, releases cash, and bundles spending into a replenishment report. |
| **Approver** (Superior / Manager / CEO) | Reviews requests and either acknowledges (approves) or rejects them. Also signs off the final replenishment. |
| **Admin** | Sets up the company, creates funds, and manages user accounts. |
| **Employee** | Basic role for visibility (no fund actions). |

> Each fund has **one approver model** — a single superior, manager, or CEO approves, not a committee.

---

## The Core Workflow

Think of money moving through **5 stages**:

```
1. REQUEST  →  2. APPROVE  →  3. RELEASE  →  4. REPLENISH  →  5. RESET
```

### 1. Request — *Incharge creates a spending request*
The custodian records an expense **before or when** cash goes out:
- Enters the **amount** and reason
- Attaches a **proof photo** (receipt / supporting document)
- Submits it for approval

### 2. Approve — *Approver acknowledges or rejects*
The assigned approver gets a notification and either:
- **Acknowledges** → the request is cleared to be paid, or
- **Rejects** → the request is sent back / closed (with a reason)

### 3. Release — *Incharge hands out the cash*
Once approved, the incharge **releases** the cash. At this point:
- The fund's **available balance goes down** by that amount
- The action is permanently logged (you cannot un-spend cash silently)

### 4. Replenish — *Incharge bundles spending into a report*
When the fund runs low, the incharge groups all the released requests into a **replenishment report** — essentially "here's everything I spent, please refund the fund."

### 5. Reset — *Approver signs off the replenishment*
An approver reviews the replenishment report and signs off. The fund's **balance is restored** back up to its budget, ready for the next cycle.

---

## Guidelines & Rules of Use

### For the Incharge (Custodian)
- ✅ **Always attach a clear proof photo** to every request — it's your evidence the money was spent correctly.
- ✅ **Only release cash after approval.** Releasing is what actually deducts the balance.
- ✅ **Replenish before you run out** — don't let the fund hit zero mid-day.
- ⚠️ Released cash **cannot be quietly reversed.** Every release is recorded in the fund's history.

### For Approvers (Superior / Manager / CEO)
- ✅ **Review the proof photo and amount** before acknowledging.
- ✅ **Reject with a clear reason** so the incharge knows what to fix.
- ✅ **Sign off replenishments promptly** so the custodian isn't left without cash.
- ⚠️ Your approval is the control point — once you acknowledge, the cash can go out.

### For Admins
- ✅ **Set up companies and funds** with the correct starting budget.
- ✅ **Create user accounts** and assign the right role — role decides what each person can do and see.
- ✅ **Reset passwords** when users are locked out (handled via email reset).
- ⚠️ A user's data is **scoped to their company** — people only see their own company's funds and requests.

### General Rules (built into the app)
- 🔒 **One company can't see another's data.** Everything is isolated by company.
- 🔒 **Status only moves in allowed directions.** A request can't jump from "draft" straight to "released" — it must follow Request → Approve → Release. The app enforces this and so does the server.
- 💰 **Money is exact.** Amounts are tracked to the centavo — no rounding surprises.
- 📜 **Every money action is logged** for audit (who, what amount, when).

---

## Quick Reference

| I want to… | Role | Where |
|------------|------|-------|
| Record an expense | Incharge | New Request |
| Approve/reject spending | Approver | Approvals |
| Hand out the cash | Incharge | Release |
| Ask for the fund to be topped up | Incharge | Replenishment |
| Sign off a top-up | Approver | Replenishment |
| Add a company / fund / user | Admin | Admin panel |
