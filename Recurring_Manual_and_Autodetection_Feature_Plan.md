# Recurring Payments — Manual + Auto‑Detection (after 2 months)
DuEasy (iOS) — PL/EN invoices & bills

## Goal
Support **two entry paths**:
1) **Manual recurring** (user marks a scanned document as recurring immediately)  
2) **Auto‑detection** (starts after 2 months; only suggests recurrence when confidence is high)

Prevent false positives (e.g., fuel from the same vendor) and avoid re-analyzing vendors that users already confirmed as recurring.

---

## 1) Product behavior overview

### 1.1 Manual recurring (immediate, after scan/import)
After successful scan + parse, show a CTA:

- **“Set as recurring”** (toggle or button)

If enabled:
- Create a `RecurringTemplate` immediately (no waiting 2 months).
- Generate the next **Expected Instance(s)** (e.g., for next 3 months).
- Future documents from this vendor are **matched** to the template and used to **update** that month’s instance (invoice number, amount, final due date).

**Important:** Manual recurring vendors are **excluded from auto‑detection** (already confirmed).

### 1.2 Auto‑detection (after 2 months)
- Only shows **suggestion cards** (“Looks recurring — create recurring reminder?”)
- Never auto‑creates templates.
- Starts when `today - firstDocumentDate >= 60 days` OR vendor has ≥3 docs spanning ≥45 days.

---

## 2) Data model (SwiftData)

### 2.1 `Document` (existing)
Ensure you have:
- `sellerName`, `sellerAddress`
- `invoiceNumber`
- `dueDate`
- `amount`, `currency`
- `iban` (optional)
- `documentCategory` (new)
- `vendorFingerprint` (new)
- `createdAt`

### 2.2 `DocumentCategory`
```swift
enum DocumentCategory: String, Codable {
  case utility, telecom, rent, insurance, subscription, invoiceGeneric
  case fuel, grocery, retail, receipt
  case unknown
}
```

### 2.3 `RecurringTemplate` (created by manual OR accepted suggestion)
Fields (minimal):
- `vendorFingerprint`
- `vendorDisplayName` (for UI)
- `dueRule`: `.dayOfMonth(Int)` + `toleranceDays` (default 3)
- `reminderOffsets`: `[Int]` (default [7, 1, 0])
- `amountRule`: `.range(min,max)` (optional; can learn over time)
- `iban` (optional)
- `active`

### 2.4 `RecurringInstance` (expected payment per cycle)
- `templateId`
- `periodKey` (e.g., `YYYY-MM`)
- `expectedDueDate`
- `status`: `expected | matched | paid | missed`
- `matchedDocumentId` (optional)
- `finalDueDate` / `finalAmount` / `invoiceNumber` (filled when matched)

### 2.5 `RecurringCandidate` (auto‑detection only)
Represents a vendor-level candidate pattern you might suggest:
- `vendorFingerprint`
- stats for due-day and amounts
- `suggestionState`: `none | suggested | dismissed | accepted`
- `lastSuggestedAt`

> If a `RecurringTemplate` exists for vendorFingerprint, you do **not** maintain or suggest `RecurringCandidate` anymore.

---

## 3) Services (MVVM/MVCC friendly)

### 3.1 `DocumentClassifierService` (offline)
Classifies documents by PL/EN keywords.  
Hard-reject categories for **auto‑detection suggestions**: `fuel, grocery, retail, receipt`.

### 3.2 `VendorFingerprintService`
Normalizes seller name (+ optional VAT/NIP) and returns `vendorFingerprint = SHA256(...)`.

### 3.3 `RecurringTemplateService`
- `createTemplate(from document, userConfig)`  ✅ manual path
- `createTemplate(from candidateSuggestion, userConfig)` ✅ auto path
- `updateTemplate(template, withMatchedDocument)` (learn amount ranges, adjust tolerance cautiously)

### 3.4 `RecurringSchedulerService`
- `generateInstances(template, monthsAhead: Int)`
- `scheduleNotifications(instance)` / update notifications when instance becomes matched

### 3.5 `RecurringMatcherService`
- `match(document) -> (template, instance)?`
- `attach(document, to instance)`:
  - set status = `matched`
  - set `invoiceNumber`, `finalAmount`, `finalDueDate`
  - update calendar event/reminders

### 3.6 `RecurringDetectionService` (auto‑detection)
- Runs only for vendors **without** an existing `RecurringTemplate`.
- Computes candidates and suggestion scores after 2 months.

---

## 4) Manual recurring flow (after scan/import)

### UX
On the “Review extracted fields” screen:
- toggle: **Recurring payment**
- if ON: ask minimal settings (optional):
  - reminder offsets (default [7,1,0])
  - “use due date day-of-month as schedule” (default ON)
  - tolerance days (default 3)

### Logic
1) Scan/import → OCR + parse → `Document`
2) Compute `vendorFingerprint`
3) User enables “Set as recurring”
4) `RecurringTemplateService.createTemplate(from: document)`
   - `dueRule.dayOfMonth = dayOfMonth(document.dueDate)`
   - store `iban` if available and user enabled “Payment autopilot”
5) `RecurringSchedulerService.generateInstances(... monthsAhead: 3)`
6) Immediately match the current document to the current month instance:
   - instance.status = `matched`
   - fill invoiceNumber/amount/dueDate
7) Subsequent documents:
   - matched by `vendorFingerprint` AND dueDate within expected ± tolerance
   - update the month instance (replace invoiceNumber, refresh amount/due date)

**Exclusion from auto‑detection:**  
Once `RecurringTemplate` exists → `RecurringDetectionService` ignores that vendor.

---

## 5) Auto‑detection rules (after 2 months)
Auto‑detection remains as previously defined, with an additional top rule:

**Rule 0:** If `RecurringTemplate` exists for `vendorFingerprint` → do not analyze, do not suggest.

Then gates + scoring:
- Gate A (category): recurring-friendly ratio ≥ 70% and reject ratio low
- Gate B (due date stability): stddev <= 3 or dominant day bucket
- Gate C (strong signal): stable IBAN OR recurring keywords OR amount stability
- Suggest only if score >= 0.75

When user accepts suggestion:
- Create `RecurringTemplate` and generate instances.

---

## 6) Matching behavior (important details)
**Must-have**
- same `vendorFingerprint`
- dueDate present
- dueDate within `expectedDueDate ± toleranceDays`

**Boost**
- IBAN match
- amount within template range

**Hard reject**
- documentCategory in `fuel/retail/receipt`
- missing dueDate (common in receipts)

---

## 7) MVVM integration points (minimal)
### Use cases
- `CreateRecurringTemplateFromDocumentUseCase` (manual)
- `DetectRecurringCandidatesUseCase` (auto, after 2 months)
- `MatchDocumentToRecurringUseCase` (runtime)

### ViewModels
- `ScanReviewViewModel`:
  - exposes `isRecurringToggle`
  - calls `CreateRecurringTemplateFromDocumentUseCase` when enabled
- `RecurringSuggestionsViewModel`:
  - shows suggestion cards and handles accept/dismiss/snooze
- `RecurringOverviewViewModel`:
  - lists templates and instances (Expected/Matched/Paid)

---

## 8) Recommended defaults (safe)
- toleranceDays = 3
- monthsAhead = 3
- reminderOffsets = [7, 1, 0]
- suggestions: in-app only (no push)
- manual recurring always available, but you may show a warning if document looks like retail/fuel

---

## Quick sanity checks
- Fuel vendor scanned repeatedly → no auto suggestion (category gate + due-date instability)
- User manually marks fuel as recurring → allowed, but warn (user intent wins)
- Telecom monthly bills → suggestion appears after 2 months OR user can set recurring on first invoice
