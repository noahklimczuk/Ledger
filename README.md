# Ledger

A private, single-user iOS budgeting app. SwiftUI + SwiftData, targeting iOS 18+, for personal
sideload/TestFlight use only.

## Status: Phase 5

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

Phase 4 (done): rules-based insights, entirely on-device (nothing leaves the phone).
- **Auto-categorization** — assigning or overriding a transaction's category teaches a
  `CategorizationRule` (merchant keyword → category, normalized so store numbers don't defeat it).
  New manual entries with a blank category and every imported/synced transaction (Plaid, CSV, OFX)
  are auto-categorized from the learned rules; the most specific keyword wins.
- **Insights engine** (`InsightsEngine`) — six detectors: categories trending up vs their 3-month
  average, budgets projected to overshoot, duplicate subscriptions, the priciest recurring charge
  to review, unusually large recent purchases, and leftover-cash change month-over-month.
- **Insights screen** (More → Insights) — the top few findings as cards, ranked by severity then
  dollar magnitude; swipe to snooze for a week or dismiss for good (persisted as `InsightState`),
  refreshed each time the screen opens.

Phase 5 (in progress): live account-linking polish for the Plaid connection.
- **Auto-sync on foreground** — opening the app triggers a background sync of the linked connection,
  throttled to at most once every few hours (`PlaidSyncCoordinator`, driven from `LedgerApp`'s
  scene-phase change). Manual "Sync Now" still works anytime.
- **Sync status** — last-synced time, last error, and a "needs sign-in" flag are persisted
  (`PlaidSyncStatusStore`) and surfaced on the Connect Wealthsimple screen.
- **Reconnect** — when Plaid returns `ITEM_LOGIN_REQUIRED`, the screen prompts a re-auth via Plaid
  Link **update mode** (`createLinkToken(accessToken:)`), which refreshes the existing item without
  a new token exchange.
- **Conflict handling** — a re-sync never overwrites your edits: transactions dedupe by external id
  (existing rows are left untouched), and a manually renamed linked account keeps its name.
- Still to do in Phase 5: linking **multiple institutions** at once, and true OS **background
  refresh** (needs the Background Modes capability enabled in Xcode) — each will be its own PR.

Phase 6 (done): automation + a debt tracker.
- **Refresh on open** — every time the app comes to the foreground it syncs the linked connection
  (no longer throttled to a few hours), re-categorizes anything new, and re-detects recurring
  series (`AppRefreshCoordinator`, driven from launch and every scene-phase `.active`).
- **Starter categories** — a common set of budgeting categories (income + essentials + discretionary)
  is seeded on first launch (`DefaultDataSeeder` / `DefaultCategoryCatalog`); you can still add,
  rename, and delete categories freely.
- **Auto-categorization out of the box** — the seeded categories ship with merchant-keyword rules,
  so transactions are categorized from a fresh install (not just after you teach a rule). A
  launch/foreground pass fills in any still-uncategorized transactions.
- **Grouped recurring** — the Recurring screen now splits detected streams into **Income**
  (paycheques, interest, regular deposits) and **Bills & Subscriptions**, with projected income and
  outflow for the next 30 days.
- **Auto-generate a budget** — Budgets → menu → "Auto-Generate from Last 3 Months" builds a budget
  for the current month from each category's average spend over the previous three months.
- **Debt tracker** (More → Debt Tracker) — track credit cards, loans, and lines of credit with a
  balance, APR, and monthly payment; each shows an estimated payoff timeline and total interest
  (standard amortization), plus a total-owed / total-monthly-payment summary.
- **Bug fixes** — removing an account you don't want to track now actually sticks: the accounts list
  hides archived accounts, and a removed **linked** account is archived (not deleted) so the next
  sync can't re-create it. The rename/save path no longer reloads the accounts list while the edit
  sheet is still presented.

Phase 7 (done): live balances + a transaction detail screen.
- **Real reported balances** — a sync now reconciles each linked account's balance to what the
  institution actually reports (`TransactionImportService.reconcileBalance`), instead of showing the
  sum of a possibly-incomplete transaction history. It back-solves the starting balance from the
  reported balance and the transactions on hand, so the dashboard total, account list, and net-worth
  chart all reflect reality; liability (credit) accounts are stored negative.
- **Live updates on open** — `AppRefreshCoordinator` is now an `@Observable` injected into the
  environment; screens reload when a background refresh finishes, so balances and transactions
  update on startup without needing to re-open a tab.
- **Transaction detail** — tapping a transaction pushes a detail screen showing the merchant, amount,
  date, account, and its current category. You can change the category right there (which also
  teaches the auto-categorization rule), or open the full editor with "Edit".

Phase 8 (done): navigation + dashboard charts.
- **Swipe between tabs** — the root is now a paged `TabView` with a custom bottom bar, so the five
  screens can be swiped left/right as well as tapped.
- **Budget → category transactions** — tapping a budget row opens `CategoryTransactionsView`, listing
  every transaction in that category for the month (with the month's total); editing a budget moved
  to a leading swipe.
- **Clear monthly income** — the dashboard shows Income / Expenses / Net tiles for the month.
- **Dashboard charts** (Swift Charts) — an income-vs-expenses bar chart and a top-spending-categories
  breakdown, alongside the existing balance/safe-to-spend/budget cards.

Not yet: the optional LLM recap, the home screen widget, envelope budgeting mode, multi-currency,
receipt photos, export, year-in-review, shared/joint view.

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
