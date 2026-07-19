# Ledger — Concept Directions

A ground-up reimagining of Ledger's visual identity. **Eighteen** completely
distinct design languages, each built to feel like a *different product* rather
than a different theme. This is a concept-exploration phase — nothing here is
final UI, and none of it preserves the current app.

> **Goal:** make choosing between these feel like choosing between entirely
> different brands. When someone sees them they should say *"this doesn't look
> like another budgeting app."*

---

## How to view

- **Interactive gallery (recommended):** open [`concepts/index.html`](concepts/index.html)
  in any browser. A left rail lists all 18 directions; click one to swap the
  stage to that concept's **live, rendered dashboard mockup** plus its full
  16-point design-language spec.
- **Hosted version:** <https://claude.ai/code/artifact/409df76b-297a-41d0-bf33-79d5958d7de5>
  (private to the owner until shared).

The gallery is a single self-contained file — no build step, no external fonts
or assets, works offline.

### About the mockups
Every concept renders a **real dashboard** (not a picture of one): hero
balance / net worth, safe-to-spend, month income·expenses·net, budgets,
spending visualization, accounts, an "Ask Ledger" AI card, recent activity,
goals and subscriptions — each drawn entirely in that concept's own visual
language. Six directions (Halo, Clay, Aqua, Obsidian, Aurora, Prism) are
full multi-panel dashboards; the other twelve lead with a **signature panel**
(the hero + that concept's signature visualization) so the identity reads
instantly, with the remaining screens described in the spec.

### Shared demo data
So the concepts read as one product in different skins, they all use the same
fictional finances (CAD, matching Ledger's real feature set — Wealthsimple
Cash, budgets with rollover, safe-to-spend, recurring/subscriptions, goals,
debt, on-device insights + AI budget suggestions):

| | |
|---|---|
| Net worth | **$128,940** (▲ $2,122 this month) |
| Liquid balance | **$36,742.35** across 4 accounts |
| July | Income **$6,240** · Expenses **$4,118** · Net **+$2,122** · Savings rate **34%** |
| Safe to spend | **$1,284** (11 days left) |
| Over budget | Dining **$312 / $300** |
| AI insight | *"Dining is 24% above your 3-month average."* |

---

## Follow-up: Bloom — a hybrid direction (first look)

After the exploration, the favourites were **Clay**, **Verdant**'s Financial
Wellness tile, and **Ember**. [`concepts/bloom.html`](concepts/bloom.html)
converges them into one product, **Bloom** (working name):

- **Clay → form** — soft, tactile pastel surfaces, the morphing balance blob,
  inset "channel" budget bars.
- **Verdant → soul** — the **Financial Wellness score** is the centrepiece: a
  co-hero on the dashboard *and* a full screen (contributing factors, trend,
  "what to tend this month").
- **Ember → warmth** — spending shows a live **burn-rate** heat meter; goals
  grow as plants (🌱→🌿→🌳).

Four screens (Dashboard, Financial Wellness, Budgets & Goals, Transactions &
Analytics) in both **Day** (light) and **Dusk** (dark) — toggle top-right.
Palette: warm ivory ground, green (wellness/growth), peach + amber (spending
energy), periwinkle (AI), deep plum ink.

- **Hosted (desktop):** <https://claude.ai/code/artifact/1ddde5c8-38a1-4a22-a3d0-ae0b0fca4de2>

**On mobile** — [`concepts/bloom-mobile.html`](concepts/bloom-mobile.html)
lays the same four screens out as phone mockups (single column, big touch
targets, a floating clay tab bar with a green FAB), in both Day and Dusk.

- **Hosted (mobile):** <https://claude.ai/code/artifact/c77cae19-2918-461f-89b7-b9ecc16eb777>

Still a first look — next step is higher-fidelity polish plus Subscriptions,
Accounts, Onboarding, Search and empty/loading/error states.

---

## Design principles applied to all 18

- **Money is the hero.** Oversized balances, strong hierarchy, magazine-editorial
  numerals, generous whitespace. Nothing generic, nothing Material/Bootstrap/iOS-default.
- **One accent, spent deliberately.** Semantic good/warning/critical colours are
  kept *separate* from each brand accent, so state reads at a glance without
  muddying the palette.
- **Colour and motion carry meaning, never alone.** Every state also has a word
  and a shape (so it survives colour-blindness and reduced-motion). All motion
  respects `prefers-reduced-motion`; numbers count up, then hold.
- **Distinct type per direction.** Each names an aspirational typeface and ships
  a documented system-font fallback, since the CSP forbids web-font CDNs.
- **Answers the five UX questions** on every screen: *What matters most? What can
  I do next? How can I save money? Am I on track? How do I feel about my money?*

---

## The eighteen directions

### Named directions

| # | Name | In one line | Light/Dark | Best for |
|---|------|-------------|-----------|----------|
| 01 | **Halo** | Money lit from within — balances glow with a soft halo on graphite | Dark-native | Calm, premium, anti-anxiety |
| 02 | **Clay** | Soft claymorphism — puffy, tactile, friendly pastels you want to press | Light-native | Approachable, human, joyful |
| 03 | **Aqua** | Liquid glass over a living teal current — Apple "Liquid Glass" energy | Dark/translucent | Most "five years from now" |

### Original languages

| # | Name | In one line | Light/Dark | Best for |
|---|------|-------------|-----------|----------|
| 04 | **Obsidian** | Monolithic graphite, headline numerals, one molten-amber accent | Dark-native | Mercury/Linear-grade restraint |
| 05 | **Aurora** | Midnight sky with an aurora that reflects your month's health | Dark-native | Emotional, ambient, novel |
| 06 | **Prism** | White light split into a spectrum — each category owns a hue | Light-native | Bright, systematic, un-corporate |
| 07 | **Pulse** | Cash flow as a vital-signs monitor; a single "financial pulse" | Dark-native | *"Am I okay?"* in one glance |
| 08 | **Meridian** | Brass-on-navy celestial — the month as a sundial, serif numerals | Dark-native | Timeless, elegant, considered |
| 09 | **Verdant** | Money you grow — a botanical Financial Wellness Score | Light-native | Calmest, wellness-minded |
| 10 | **Neo** | Nothing-style: monochrome, dot-matrix, one red signal | Both (inverts) | Boldest anti-fintech statement |
| 11 | **Flux** | Money as motion — a live cashflow river (Sankey) is the dashboard | Dark-native | *"Where does it all go?"* |
| 12 | **Atlas** | Cartographic — net worth is altitude, goals are summits | Dark-native | Goal-driven, aspirational |
| 13 | **Ember** | Firelight — your balance glows, spending has a visible "burn rate" | Dark-native | Warmest, most intimate |
| 14 | **Cobalt** | Bold, precise electric-blue fintech — sharper than Stripe | Light-native | Broad appeal, instant credibility |
| 15 | **Slate** | Architectural — budgets are load-bearing columns, hazard yellow | Light-native | Engineered, honest, structural |
| 16 | **Orbit** | Your money as a solar system — accounts orbit net worth | Dark-native | Multi-account net worth, showpiece |
| 17 | **Nocturne** | Moonlit calm — a moon that waxes as your goal fills | Dark-native | Peace of mind, late-night checks |
| 18 | **Grid** | Swiss International Typographic — rigorous grid, Helvetica, one red | Light-native | Timeless, precise, design-literate |

Each direction in the gallery documents all sixteen requested deliverables:
philosophy, colour, typography, layout, components, charts, navigation, motion,
iconography, illustration, widgets, AI integration, accessibility, a unique
interaction, dark/light behaviour, tablet/desktop behaviour — plus *why you'd
choose it*.

---

## Data-visualization ideas explored (no boring bar charts)

Radial spending rings (Halo) · rising-water budget levels & cashflow waves
(Aqua) · aurora health bands (Aurora) · the spectrum-of-the-month (Prism) ·
EKG cash-flow trace (Pulse) · sundial month-pace (Meridian) · wellness gauge &
growth curves (Verdant) · dot-matrix budgets (Neo) · Sankey cashflow river
(Flux) · topographic elevation & summits (Atlas) · burn-rate heat meter (Ember) ·
paired income/expense bars (Cobalt) · load-bearing budget columns (Slate) ·
orbital account system (Orbit) · moon-phase goals (Nocturne) · immaculate
typographic data tables (Grid).

## AI ("Ask Ledger") explored per direction

A daily briefing that adopts each brand's voice — a doctor's diagnosis (Pulse),
a gardener (Verdant), an almanac (Meridian), mission control (Orbit), a
structural engineer (Slate), a terse machine readout (Neo), an editor's
one-liner (Grid) — always: one insight, one number, one recommended action.

---

## Choosing a direction

A suggested shortlist depending on the brand you want Ledger to be:

- **Premium & calm, flagship:** Halo · Aqua · Obsidian
- **Warm & human, mass-market:** Clay · Verdant · Ember
- **Bold & unmistakable:** Neo · Grid · Slate
- **Emotional & novel:** Aurora · Pulse · Nocturne
- **Spatial & motivating:** Orbit · Atlas · Flux
- **Safe, credible, fast to ship:** Cobalt · Prism

Next step: pick 2–3 favourites to take to higher fidelity (full screen set —
Transactions, Budget Detail, Analytics, Goals, Subscriptions, Accounts, Search,
Onboarding, Login, empty/loading/error states, tablet + desktop), then build one
into a real component library.

---

*Concept exploration · not final UI · demo data is fictional.*
