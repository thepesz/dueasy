# Home Screen (Glance Dashboard) — Developer Spec (iOS)
DuEasy — Invoices & Payment Reminders (B2C + small business)

## Goals
Home should feel **Apple‑pro**, minimal, and readable “at a glance”.
- No full document list (Documents is a separate tab/view)
- No scan button here (Scan is separate)
- Home answers in 3 seconds:
  1) **How much is due soon?**
  2) **Is anything overdue / missing / needs attention?**
  3) **What are the next 1–3 payments?**

---

## Layout Overview (top → bottom)

### Section 0 — Navigation Bar
- Title: **Home**
- Right side: **Status chip** (small)
  - `Offline` (Free/offline mode) OR `Pro` (cloud enabled)
  - optional: small sync dot (green/gray), but avoid noise

### Section 1 — Hero Card (Full width)
**“Due in next 7 days”**
- Large total amount (primary number)
- Subtext: `X invoices • Next due: <date>`
- Small status counters (capsules):
  - `Overdue <n>` (only if n>0)
  - `Due soon <n>` (only if n>0)
  - keep max 2 capsules visible

### Section 2 — Two Tiles (2-column grid)
Two square-ish tiles (same height), minimal content.

**Tile A: Overdue**
- If there are overdue unpaid items:
  - Title: `Overdue`
  - Amount: total overdue value
  - Subtext: `Oldest: <n> days`
  - CTA: `Review` → opens Calendar filtered to overdue
- If none:
  - Title: `Overdue`
  - Body: `All clear ✅`

**Tile B: Recurring**
- Title: `Recurring`
- Body: `Active: <n>`
- Subtext: `Next: <vendor> in <n>d` (if available)
- If missing recurring bill detected this cycle:
  - show small line: `Missing: <n>` (optional)
- CTA: `Manage` → recurring management view

### Section 3 — Next 3 Payments (Compact List)
Container card with header `Next payments`.
- Show up to 3 rows (not more on Home)
- Each row:
  - left: vendor name (1 line)
  - right: amount
  - second line (small): `Due: <date>` OR `Overdue: <n>d`
- Footer link: `See all upcoming` → Calendar upcoming view (not Documents)

### Section 4 — Month Summary (Donut Chart Card)
Card title: `This month — Payment status`
- Left: donut chart (3 segments max)
- Center text inside donut:
  - `X% paid`
  - `Y invoices`
- Right: vertical stats:
  - `Paid: <n>`
  - `Due: <n>`
  - `Overdue: <n>`
- Bottom line (small): `Unpaid total: <amount>`

> No legend. The right-side numbers replace the legend.

---

## Data Definitions (Source of Truth)
Assume `PaymentItem` (or derived from `Document`) has:
- `dueDate: Date`
- `amount: Decimal`
- `currency: String` (ISO 4217)
- `isPaid: Bool`
- optional: `paidAt: Date?`
- optional: `vendorDisplayName: String`
- optional: `recurringTemplateId: UUID?`

### Upcoming window (Hero + list)
- Upcoming = unpaid items where `dueDate ∈ [today, today+7]`
- Overdue = unpaid items where `dueDate < today`

### Hero Card metrics
- `dueIn7DaysTotal = sum(amount of Upcoming)`
- `dueIn7DaysCount = count(Upcoming)`
- `nextDueDate = min(dueDate among Upcoming)` (else fallback to min among unpaid future)

### Overdue Tile metrics
- `overdueTotal = sum(amount of Overdue)`
- `oldestOverdueDays = daysBetween(min(dueDate among Overdue), today)`

### “Next 3 payments” rows
- candidate set = unpaid items with `dueDate >= today` plus (optionally) overdue items if you want them visible
- recommended ordering:
  1) overdue first (sorted by dueDate ascending)
  2) then upcoming future (sorted by dueDate ascending)
- take first 3

### Recurring Tile metrics
From `RecurringTemplate` + `RecurringInstance`:
- `activeRecurringCount = count(templates where active == true)`
- `nextRecurringInstance = min(instance.expectedDueDate among instances with status expected|matched)`
- `missingRecurringCount` (optional): instances expected for current month that are not matched after a grace window

### Month Summary (Donut)
Define “this month” based on **dueDate month** (recommended for user intuition).

For the current month (by dueDate):
- `monthPaidCount` = count(items with dueDate in this month AND isPaid == true)
- `monthDueCount` = count(items with dueDate in this month AND isPaid == false AND dueDate >= today)
- `monthOverdueCount` = count(items with dueDate in this month AND isPaid == false AND dueDate < today)

Donut segments:
- Paid = `monthPaidCount`
- Due = `monthDueCount`
- Overdue = `monthOverdueCount`

Center:
- `paidPercent = monthPaidCount / max(1, totalMonthCount)`

Bottom line:
- `monthUnpaidTotal = sum(amount for monthDue + monthOverdue)`

---

## UI/Interaction Rules
- Home should avoid clutter:
  - If a section has no content, simplify it.
- **Conditional rendering**
  - If no upcoming + no overdue: Hero shows `No upcoming payments` + subtext `You're all set`
  - If overdueTotal == 0: Overdue tile shows `All clear ✅`
  - If recurring not used: Recurring tile can show `Set up recurring` (CTA to recurring screen)
- Navigation targets:
  - Hero tap → Calendar upcoming
  - Overdue tile CTA → Calendar overdue filter
  - Recurring tile CTA → Recurring management
  - Next payments “See all” → Calendar upcoming

---

## Visual Guidelines (Apple-like)
- Spacing:
  - outer padding: 16
  - section spacing: 12
- Card style:
  - corner radius: 16–20
  - subtle shadow or material background (keep consistent)
- Typography:
  - hero amount: `largeTitle` (rounded design if desired)
  - titles: `headline`
  - secondary text: `subheadline` / `footnote`
- Colors:
  - minimal; use semantic colors
  - red only for overdue labels, not whole cards

---

## Empty States

### No documents at all
- Hero: `No payments yet`
- Subtext: `Add your first invoice to start tracking due dates`
- Do not add a scan button here (Scan is separate), but allow a subtle text link: `Go to Scan`

---

## Implementation Notes (MVVM-friendly)
- `HomeViewModel` exposes a single `HomeViewState` struct with:
  - hero metrics
  - overdue tile metrics
  - recurring tile metrics
  - next payments rows (max 3)
  - month donut metrics
- Avoid doing filtering in the View; compute in VM / use case.
- Use a `HomeMetricsService` (pure) for testable calculations.

---

## Acceptance Criteria
- Home fits comfortably on a typical iPhone screen with minimal scrolling.
- User can understand **due soon total** and **overdue risk** in < 3 seconds.
- Donut chart is readable without legend and matches the right-side numbers.
- No document list shown on Home (only top 3 payment rows).
- Works in Free/offline mode (no backend required).
