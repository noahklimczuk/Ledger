# Ledger

A private, single-user iOS budgeting app. SwiftUI + SwiftData, targeting iOS 18+, for personal
sideload/TestFlight use only.

## Status: Phase 5

Phase 1 (done): multi-account tracking, manual transaction entry with splits, custom categories,
monthly budgets with rollover, a dashboard (balances, safe-to-spend, budget progress, recent
transactions), and Face ID lock on launch. Wealthsimple bank-account linking is included (via a
direct connection to Wealthsimple's own API — see below; pulled forward from the original
later-phase plan), behind the swappable `TransactionSource` protocol.

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
  New manual entries with a blank category and every imported/synced transaction (Wealthsimple,
  CSV, OFX) are auto-categorized from the learned rules; the most specific keyword wins.
- **Insights engine** (`InsightsEngine`) — six detectors: categories trending up vs their 3-month
  average, budgets projected to overshoot, duplicate subscriptions, the priciest recurring charge
  to review, unusually large recent purchases, and leftover-cash change month-over-month.
- **Insights screen** (More → Insights) — the top few findings as cards, ranked by severity then
  dollar magnitude; swipe to snooze for a week or dismiss for good (persisted as `InsightState`),
  refreshed each time the screen opens.

Phase 5 (in progress): live account-linking polish for the Wealthsimple connection.
- **Auto-sync on foreground** — opening the app triggers a background sync of the linked connection,
  throttled to at most once every few hours (`WealthsimpleSyncCoordinator`, driven from `LedgerApp`'s
  scene-phase change). Manual "Sync Now" still works anytime.
- **Sync status** — last-synced time, last error, and a "needs sign-in" flag are persisted
  (`WealthsimpleSyncStatusStore`) and surfaced on the Connect Wealthsimple screen.
- **Reconnect** — the stored session refreshes its own access token from the refresh token on each
  sync; when the refresh token itself expires, the screen flags "needs sign-in" and the user signs
  in again to mint a fresh session.
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
- **Clear monthly income** — the dashboard shows Income / Expenses / Net tiles for the month, labelled
  with the current month so the scope is unambiguous.
- **Dashboard charts** (Swift Charts) — a (skinny-barred) income-vs-expenses chart and a
  top-spending-categories breakdown, alongside the existing balance/safe-to-spend/budget cards.
- **Live transactions list** — the Transactions tab now reads via SwiftData `@Query`, so it updates
  automatically on any change (sync, add, edit, delete) with no manual reload.
- **Reliable delete** — budget rows and transaction rows gained a long-press context menu (Edit /
  Delete), so those actions stay reachable even where the paged-tab swipe competes with row swipes.

Phase 9 (done): a bug-fix / polish / feature-completion pass, plus AI budget suggestions.
- **Fixes** — the linked sync skips non-final transactions (they re-post under a new id, defeating
  dedup) and scopes each pull per account; archived (removed) accounts' transactions no longer
  count toward any aggregate (dashboard, budgets, reports, net worth, insights, recurring);
  user-entered amounts parse robustly ("1,234.56" no longer silently read as 1); deleting a
  category cleans up its budgets and learned rules. (The bank link ran through Plaid at the time;
  it was later replaced by a direct Wealthsimple connection — see "Connecting Wealthsimple Cash".)
- **Budget rollover compounds** across consecutive rollover-enabled months (bounded to 12), with
  overspent months drawing the accumulated carry down.
- **Recurring forecasts count every occurrence** in the window — a weekly charge reserves ~4-5
  hits per month in the 30-day outflow and Safe to Spend, not one.
- **Manual entry** gained an Expense/Income control: amounts are typed unsigned and default to
  expense, so "12.50" for a coffee no longer records as income.
- **AI budget suggestions** — Budgets → "Suggest a Budget" builds a reviewable per-category
  proposal from the last 6 months. Aggregation is fully on-device; with a free Google Gemini API
  key (entered in the sheet, stored in the Keychain) the summary — aggregated category totals only,
  never transactions — is sent to the Gemini API for tailored amounts and plain-English
  rationales. No key or no network falls back to the on-device numbers. Nothing is written until
  Apply. (Gemini's free tier needs only a Google account — no credit card — via
  aistudio.google.com/apikey; it replaced the paid Anthropic integration.)
- **Accessibility & onboarding** — VoiceOver summaries for charts and budget bars, tab-bar
  selected states, Dynamic Type on hero figures, and a first-run getting-started guide on the
  empty dashboard.
- **Tests** — a `LedgerTests` target (Swift Testing) covering parsing, categorization matching,
  recurring detection, rollover math, Safe to Spend, debt payoff, net worth, and the budget
  suggestion aggregation.

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

## Connecting Wealthsimple Cash (direct)

The "Connect Wealthsimple" flow links your **Wealthsimple Cash** account by talking to
Wealthsimple's own API the same way the Wealthsimple web app does — you sign in with your
Wealthsimple email/password (and 2-step code when prompted). There's **no third-party aggregator,
no API keys, and no paid plan**: it's free.

> **Why not Plaid?** The earlier version routed this through [Plaid](https://plaid.com), which
> needs a paid **Production** plan (and manual approval) to see real data, and whose Wealthsimple
> coverage in Canada is unreliable. A *brokerage* aggregator (e.g. SnapTrade) can only see
> Wealthsimple's trading/investment accounts, never Wealthsimple Cash. Signing in directly is the
> free path that actually reaches Cash, so the Plaid integration was removed in favour of it.

Setup — there's nothing to configure ahead of time:

1. In the app: More → Connect Wealthsimple → enter your Wealthsimple email and password → **Connect
   Wealthsimple**.
2. If your account has 2-step verification on (it should), Wealthsimple sends a code and the screen
   reveals a field for it — enter it and tap **Verify & Connect**.
3. On success the app pulls in your Cash account and its transaction history, then re-syncs
   automatically on foreground (throttled) and via "Sync Now".

How it works (see `Services/TransactionImport/Wealthsimple/`):

- **Auth** — a one-time bootstrap scrapes the login page for the device id (`wssdi` cookie) and the
  web app's OAuth `client_id`, then an OAuth **password grant** against
  `api.production.wealthsimple.com` returns access + refresh tokens (`WealthsimpleAPIClient`).
- **Data** — accounts and the Cash **activity feed** are read from the GraphQL endpoint at
  `my.wealthsimple.com/graphql` (`FetchAccounts`, `FetchActivityFeedItems`). Wealthsimple's
  `amountSign` already matches Ledger's convention (negative = money out).
- **Refresh** — each sync refreshes the access token from the refresh token; when the refresh token
  expires the screen flags "needs sign-in".

**Caveat:** Wealthsimple has no public/official API, so `WealthsimpleAPIClient`/`WealthsimpleModels`
follow the shapes used by the community `ws-api` clients (reverse-engineered from the web app).
Endpoint/field names can change, and everything decodes defensively (optional fields,
`convertFromSnakeCase`) so a mismatch degrades to missing data rather than a crash. The pure
API-shape → Ledger mapping is unit-tested (`WealthsimpleMappingTests`).

The login session (access + refresh tokens, device/session ids) is stored in the iOS Keychain only
— never in UserDefaults, Info.plist, or source control. Your password is sent only to Wealthsimple
to sign in and is not persisted.

## Architecture

- **Models/** — SwiftData `@Model` types (source of truth, fully offline).
- **ViewModels/** — `@MainActor @Observable` classes, one per screen; own `ModelContext` reads/writes.
- **Views/** — SwiftUI, grouped by feature (Dashboard, Accounts, Transactions, Budgets, Categories, Integrations, Shared).
- **Services/** — `TransactionImport/` (the `TransactionSource` protocol + Wealthsimple and CSV/OFX
  adapters), `Security/` (Keychain, Face ID), `Formatting/` (CAD currency, en_CA dates).
- **Utilities/** — small stateless helpers (safe-to-spend math, hex color).

`TransactionSource` is the seam for swapping data sources: manual entry writes to SwiftData
directly (no source needed), the direct Wealthsimple connection and CSV/OFX import are real
implementations, and another source (e.g. a self-hosted proxy) can be added later as an additional
conformance without touching call sites.
