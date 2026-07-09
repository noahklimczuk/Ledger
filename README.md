# Ledger

A private, single-user iOS budgeting app. SwiftUI + SwiftData, targeting iOS 18+, for personal
sideload/TestFlight use only.

## Status: Phase 3

Phase 1 (done): multi-account tracking, manual transaction entry with splits, custom categories,
monthly budgets with rollover, a dashboard (balances, safe-to-spend, budget progress, recent
transactions), and Face ID lock on launch. Wealthsimple bank-account linking via Plaid is included
(pulled forward from the original later-phase plan), behind the swappable `TransactionSource`
protocol.

Phase 2 (done): CSV and OFX/QFX file import (More → Import CSV / OFX). Pick a file, choose the
target account, map columns (CSV only — OFX carries structured fields), preview which rows are new
vs. duplicates, then import. Dedup is deterministic (CSV rows hash to a stable id including an
occurrence index for legitimate same-day repeats; OFX uses the bank's FITID), so re-importing the
same or an overlapping export is idempotent. Both live behind the same `TransactionSource` seam
(`CSVTransactionSource`, `OFXTransactionSource`).

Phase 3 (done): recurring detection, reports, net worth, savings goals, and bill reminders,
reachable from the More tab.
- **Recurring** — detects subscriptions/regular bills from history by spacing regularity
  (weekly→yearly), forecasts the next 60 days of charges with a 30-day outflow total, and lets you
  ignore/restore a series. Persisted as `RecurringSeries`, refreshed on open.
- **Reports** (Swift Charts) — date-range picker (this/last month, 3/6 months, this year, custom);
  income/expense/net tiles; net-worth line chart (derived from transactions, no snapshots needed);
  spending-by-category bars (split-aware); grouped income-vs-expense bars; month-over-month delta.
- **Savings Goals** — target amount + optional date, progress bars, required monthly contribution,
  swipe to add a contribution.
- **Bill Reminders** — local notifications only (no server), optional recurrence, notify-days-before,
  swipe "Paid" to advance a recurring bill to its next due date.

Not yet: the rules-based insights engine, the optional LLM recap, the home screen widget, envelope
budgeting mode, multi-currency, receipt photos, export, year-in-review, shared/joint view.

## Building

This was written on a machine without Xcode, so it has **not been compiled or run**. Open
`Ledger/Ledger.xcodeproj` in Xcode (26.5+), select a simulator or your device, and build (⌘B).
The project uses Xcode's file-system-synchronized groups, so no `xcodegen`/CocoaPods/SPM step is
needed — everything under `Ledger/Ledger/` is picked up automatically by the target.

If the build fails, paste the exact error text back — that's the fastest way to fix it without
a Mac-side debugging loop.

### First-run checklist (nothing here can be verified without a device/simulator)

1. Launch → Face ID/passcode prompt (`AppLockView`) should appear and unlock into the dashboard.
2. Accounts tab → add a chequing account with a starting balance.
3. Transactions tab → add a transaction against it, then edit it to add a split across two
   categories (create categories first under More → Categories if the list is empty).
4. Budgets tab → set a monthly budget for a category, confirm the progress bar reflects the
   transaction you added.
5. Dashboard → confirm total balance, safe-to-spend, and month spending/budget numbers match
   what you'd expect from steps 2-4.
6. Swipe actions on a transaction row: mark reviewed (leading swipe), delete (trailing swipe).

## Connecting Wealthsimple bank accounts (Plaid)

The "Connect Wealthsimple" flow links your **bank** accounts — Wealthsimple Cash, chequing and
savings — through [Plaid](https://plaid.com), a licensed account aggregator that covers
Wealthsimple's depository products in Canada. Your Wealthsimple credentials are entered on Plaid's
own hosted login page and never touch this app.

> **Why Plaid?** A *brokerage* aggregator (e.g. SnapTrade) can only see Wealthsimple's
> trading/investment accounts, never Wealthsimple Cash. Plaid covers Wealthsimple's depository
> products, so the Connect Wealthsimple screen uses it to pull in bank accounts and their
> transactions.

Setup:

1. Create a developer account at [dashboard.plaid.com](https://dashboard.plaid.com) and copy your
   `client_id` + a `secret`. Real Wealthsimple data requires **Production** keys with the
   `transactions` product enabled (Sandbox only returns fake test banks).
2. In the Plaid dashboard, enable **Hosted Link** and add `ledger://plaid-callback` as an allowed
   redirect URI (required for the `ASWebAuthenticationSession` callback in `PlaidConnectSession`).
3. In the app: More → Connect Wealthsimple → enter the client ID / secret, pick the environment →
   Save → Connect Wealthsimple. This opens Plaid's Hosted Link (institution search → Wealthsimple
   login → account selection), exchanges the resulting public token for an access token, and pulls
   in accounts + transaction history.

Balances/transactions sync via `/accounts/balance/get` and `/transactions/get`; Plaid signs
amounts the opposite way from Ledger (Plaid positive = money out), so `PlaidTransactionSource`
negates them to match Ledger's convention (negative = money out).

**Caveat:** `PlaidAPIClient`/`PlaidModels` were written against Plaid's published docs
(plaid.com/docs/api) without a live account to test against — endpoint paths and the Hosted Link
public-token retrieval (`/link/token/get`) follow current docs, but exact response field
names/casing may need small fixes once you can see real API responses. Everything decodes
defensively (optional fields, `convertFromSnakeCase`) so a mismatch degrades to missing data
rather than a crash.

Credentials (`client_id`, `secret`, the generated `access_token`) are stored in the iOS Keychain
only — never in UserDefaults, Info.plist, or source control.

## Architecture

- **Models/** — SwiftData `@Model` types (source of truth, fully offline).
- **ViewModels/** — `@MainActor @Observable` classes, one per screen; own `ModelContext` reads/writes.
- **Views/** — SwiftUI, grouped by feature (Dashboard, Accounts, Transactions, Budgets, Categories, Integrations, Shared).
- **Services/** — `TransactionImport/` (the `TransactionSource` protocol + Plaid adapter),
  `Security/` (Keychain, Face ID), `Formatting/` (CAD currency, en_CA dates).
- **Utilities/** — small stateless helpers (safe-to-spend math, hex color).

`TransactionSource` is the seam for swapping data sources: manual entry writes to SwiftData
directly (no source needed), Plaid and CSV/OFX import are real implementations, and another
source (e.g. a self-hosted proxy) can be added later as an additional conformance without
touching call sites.
