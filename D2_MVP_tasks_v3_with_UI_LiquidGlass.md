# D2 (InvoiceSnap Calendar) — MVP Delivery Tasks (iOS, fully local)

Audience: iOS developers  
Goal: Production-grade local MVP (no backend), clean architecture, single data flow, no shortcuts.

---

## 0) Decisions (architecture + conventions)

> Note: Iteration 1 is fully local, but must be built with protocol-based services and use cases so Iteration 2 (backend + AI) requires minimal refactoring.

### Architecture (recommended)
- **SwiftUI + MVVM** with a small, explicit layering:
  - **UI (Views)**: SwiftUI screens only, no business logic
  - **ViewModels**: UI state + user actions, calls use-cases/services
  - **Domain (Use Cases)**: “Add Document”, “Parse Invoice”, “Schedule Reminders”, “Add Calendar Event”
  - **Data layer**:
    - **Repository** for persistence (SwiftData)
    - **Services** for OCR, parsing, calendar, notifications, file storage
- **Single source of truth**: SwiftData store is the canonical data store.
- **Single data flow**: Views → ViewModels → Use Cases/Services → Repository → SwiftData → ViewModels → Views


---

## UI foundations (iOS 26 / SwiftUI “Liquid Glass”)

Goal: Build a modern UI that matches current iOS design while staying accessible and stable.

### Non-negotiable foundations (names you can point to)
- **Apple Human Interface Guidelines (HIG)** as the source of truth:
  - Motion (feedback, state, hierarchy)
  - Materials/Transparency (readability + contrast)
  - Accessibility (Dynamic Type, Reduce Motion, Reduce Transparency, Increase Contrast)
- **SwiftUI Liquid Glass**:
  - Prefer **standard SwiftUI components** (they adopt Liquid Glass automatically)
  - For custom surfaces, use the **Liquid Glass effect API** (e.g. glass effects) instead of “home‑made blur hacks”
- **System-first UI**:
  - Use NavigationStack, toolbars, sheets, confirmation dialogs, native pickers
  - Avoid heavy custom chrome that fights the system

### Practical rules for this app
- Keep the core flow “fast and calm”:
  - 1 primary action per screen (“Scan”, “Review”, “Save & Add to Calendar”)
  - Clear status states (Draft / Scheduled / Paid) with simple icons and text
- Use Liquid Glass where it helps, not everywhere:
  - Glass surfaces for navigation/toolbars and light overlays
  - Keep the document preview + editable fields on solid, readable backgrounds
- Accessibility is mandatory (Liquid Glass can be visually intense):
  - Respect **Reduce Transparency** and **Increase Contrast** (fall back to more solid backgrounds when enabled)
  - Respect **Reduce Motion** (avoid “floaty” animations; keep transitions subtle)
  - Support Dynamic Type for all text

### Implementation guidance (developer-facing)
- Introduce a small **Design System** early:
  - Spacing scale, corner radius, typography tokens, elevations (shadows), colors
  - A single “Card” component that can render in:
    - solid mode (accessible fallback)
    - glass mode (Liquid Glass)
- Add environment-driven UI fallbacks:
  - If Reduce Transparency is enabled → disable glass surfaces (use solid)
  - If Reduce Motion is enabled → disable complex morphing/merging animations

### Deliverable (Iteration 1)
- MVP UI uses mostly system components + a small set of reusable components:
  - DocumentRow
  - StatusBadge
  - PrimaryButton
  - Card (glass/solid)
- Avoid custom tab bars or experimental navigation patterns in MVP.

### Tech choices
- UI: **SwiftUI**
- Persistence: **SwiftData** (fallback: Core Data if needed)
- Scanning: **VisionKit** document scanner
- OCR: **Vision** (VNRecognizeTextRequest) — on-device
- Calendar: **EventKit**
- Local notifications: **UserNotifications**
- Concurrency: **async/await**
- Dependency injection: simple constructor injection (+ one App container)

### Document scope (MVP)
- Document types in UI: **Invoice / Contract / Receipt**
- **Only Invoice is functional** in MVP:
  - Contract/Receipt can be “Coming soon” (disabled) or “Save only” (no automation). Decide once and keep consistent.

---

## 1) Project setup

- [ ] Create Xcode project (iOS 17+ recommended), configure signing, bundle id
- [ ] Add app configuration:
  - [ ] Info.plist usage strings: Camera, Photo Library (if used), Calendar, Notifications
  - [ ] Localizations scaffold (en, pl optional)
- [ ] Define folder/module structure:
  - [ ] App/
  - [ ] Features/Documents/ (Views, ViewModels)
  - [ ] Domain/UseCases/
  - [ ] Data/ (Repositories, SwiftData models)
  - [ ] Services/ (OCR, Parser, Calendar, Notifications, FileStorage)
  - [ ] Shared/UIComponents/
  - [ ] Shared/Utilities/
- [ ] Create Dependency Container (AppEnvironment):
  - [ ] Instantiate repositories/services once
  - [ ] Pass dependencies to ViewModels via constructors (no globals)

---

## 2) Data model (SwiftData)

### Core entities
- [ ] `DocumentType` enum: `invoice`, `contract`, `receipt`
- [ ] `DocumentStatus` enum: `draft`, `scheduled`, `paid`, `archived`
- [ ] `FinanceDocument` (SwiftData @Model) with fields:
  - [ ] id (UUID)
  - [ ] type (DocumentType)
  - [ ] title/vendorName (String)
  - [ ] amount (Decimal)
  - [ ] currency (String, default "PLN")
  - [ ] dueDate (Date?)
  - [ ] createdAt (Date)
  - [ ] status (DocumentStatus)
  - [ ] notes (String?)
  - [ ] sourceFileURL (String)  // local file path
  - [ ] calendarEventId (String?) // EventKit identifier
  - [ ] reminderOffsetsDays ([Int]) // e.g. [7,1,0]
  - [ ] notificationsEnabled (Bool)
- [ ] SwiftData configuration:
  - [ ] ModelContainer setup
  - [ ] Migration plan (even if empty now) + versioning convention

---

## 3) Services (production-ready)

### 3.1 FileStorageService
- [ ] Save scanned images/PDF into app sandbox (Documents/ or Application Support/)
- [ ] Provide APIs:
  - [ ] `saveDocumentFile(data|images) -> urlString`
  - [ ] `loadDocumentFile(urlString) -> Data/UIImage`
  - [ ] `deleteDocumentFile(urlString)`
- [ ] Handle failures + return typed errors

### 3.2 ScannerService (VisionKit)
- [ ] Integrate VisionKit document camera
- [ ] Output: high-quality image(s) + optionally combined PDF (choose one approach)
- [ ] Provide API to return a normalized format for OCR (UIImage list)

### 3.3 OCRService (Apple Vision)
- [ ] Implement `recognizeText(images) -> String`
- [ ] Configure languages (e.g. Polish + English)
- [ ] Add basic quality handling:
  - [ ] if OCR returns empty/low confidence, surface warning

### 3.4 InvoiceParsingService (heuristics)
- [ ] Implement `parseInvoice(text) -> ParsedInvoice`
- [ ] `ParsedInvoice` fields:
  - [ ] amount (Decimal?)
  - [ ] dueDate (Date?)
  - [ ] vendorName (String?)
  - [ ] invoiceNumber (String?)
- [ ] Parsing rules v1:
  - [ ] Find candidate dates (dd.mm.yyyy, yyyy-mm-dd)
  - [ ] Prefer dates near keywords: "Termin płatności", "Due date", "Płatność do"
  - [ ] Find currency amounts (PLN, zł, EUR) and select the largest plausible total
- [ ] Always allow manual correction in UI (parsing is “suggestion”)

### 3.5 CalendarService (EventKit)
- [ ] Request calendar access with clear user messaging
- [ ] Add/update/remove event:
  - [ ] create event in selected calendar
  - [ ] store `calendarEventId` in document
  - [ ] update event when dueDate/title/amount changes
  - [ ] remove event on delete
- [ ] Option: create dedicated calendar "Invoices" (MVP: configurable)

### 3.6 NotificationService (UserNotifications)
- [ ] Request permission
- [ ] Schedule notifications based on dueDate and offsets (e.g. 7/1/0 days)
- [ ] Update/cancel notifications when dueDate changes or document deleted
- [ ] Persist offsets in document and respect global defaults from settings

### 3.7 Error handling + logging
- [ ] Define `AppError` types per service
- [ ] Add lightweight logging (OSLog)
- [ ] Surface user-friendly messages (no raw errors in UI)

---

## 4) Domain Use Cases (single data flow)

- [ ] `CreateDocumentUseCase`
  - [ ] create SwiftData record with type=invoice, status=draft
- [ ] `ScanAndAttachFileUseCase`
  - [ ] scan/import file
  - [ ] save via FileStorageService
  - [ ] attach `sourceFileURL` to document
- [ ] `ExtractAndSuggestFieldsUseCase`
  - [ ] run OCR
  - [ ] run invoice parsing
  - [ ] return suggestions to ViewModel
- [ ] `FinalizeInvoiceUseCase`
  - [ ] validate fields
  - [ ] persist final values
  - [ ] add/update calendar event
  - [ ] schedule notifications
  - [ ] update status to `scheduled`
- [ ] `MarkAsPaidUseCase`
  - [ ] set status=paid
  - [ ] optionally cancel future notifications (decision)
- [ ] `DeleteDocumentUseCase`
  - [ ] remove calendar event
  - [ ] cancel notifications
  - [ ] delete stored file
  - [ ] delete SwiftData record

---

## 5) UI Screens (SwiftUI) + ViewModels

### 5.1 Onboarding + Permissions
- [ ] `OnboardingView`
  - [ ] value proposition + “Get started”
- [ ] `PermissionsViewModel`
  - [ ] request camera/scanner, calendar, notifications
  - [ ] show rationale text before system prompt

### 5.2 Document List (Home)
- [ ] `DocumentListView`
  - [ ] segmented filter: Pending/Scheduled/Paid/All
  - [ ] search (vendor/title)
  - [ ] empty state
- [ ] `DocumentListViewModel`
  - [ ] fetch from SwiftData via repository
  - [ ] handle delete action (calls use case)

### 5.3 Add Document (type + scan)
- [ ] `AddDocumentView`
  - [ ] DocumentType picker (Invoice enabled; others disabled or Save-only)
  - [ ] buttons: Scan / Import PDF (optional)
- [ ] `AddDocumentViewModel`
  - [ ] creates draft document
  - [ ] launches scanner/import and attaches file

### 5.4 Review & Edit Extracted Data (critical screen)
- [ ] `DocumentReviewView`
  - [ ] preview image(s)
  - [ ] editable fields: vendor, amount, dueDate, invoiceNumber (optional)
  - [ ] reminder offsets UI (simple toggles)
  - [ ] CTA: “Save & Add to Calendar”
- [ ] `DocumentReviewViewModel`
  - [ ] runs OCR + parsing (async)
  - [ ] populates suggestions
  - [ ] validates input before finalizing

### 5.5 Document Details
- [ ] `DocumentDetailView`
  - [ ] show fields + status
  - [ ] actions: Edit, Mark Paid, Remove from Calendar, Delete
- [ ] `DocumentDetailViewModel`
  - [ ] updates via use cases; keeps calendar + notifications in sync

### 5.6 Settings
- [ ] `SettingsView`
  - [ ] default reminder offsets (e.g. 7/1/0)
  - [ ] default calendar selection (or toggle “Use Invoices calendar”)
  - [ ] help/contact
- [ ] `SettingsViewModel` (persist settings locally)

### UI quality (production mindset)
- [ ] Accessibility labels for key controls
- [ ] Loading states for OCR/parsing
- [ ] Clear error banners + retry options
- [ ] Consistent formatting for currency and dates

---

## 6) Validation rules (MVP)

- [ ] Amount must be > 0
- [ ] Due date must be >= today (allow past with warning + manual override if needed)
- [ ] Vendor/title can be empty but warn (optional)
- [ ] If calendar permission denied:
  - [ ] allow saving document without calendar event (but clearly show “Not added to calendar”)

---

## 7) Testing (minimum but real)

### Unit tests
- [ ] InvoiceParsingService tests:
  - [ ] multiple date formats
  - [ ] multiple amounts (select correct)
  - [ ] keywords near due date
- [ ] Notification scheduling logic tests (offset calculations)

### Integration tests (light)
- [ ] Create document → attach file → finalize → verify eventId saved (mock CalendarService)

### Manual test checklist
- [ ] Scan sharp invoice → OCR suggestions ok
- [ ] OCR fails → user can enter manually
- [ ] Save & add to calendar works
- [ ] Notifications fire at expected times (use short offsets for testing)
- [ ] Edit due date updates calendar + notifications
- [ ] Delete removes everything cleanly

---

## 8) Release readiness

- [ ] App icon + basic branding
- [ ] Privacy notes (local processing, no upload)
- [ ] Simple in-app FAQ (why permissions, how data is stored)
- [ ] Basic crash-free run on real device
- [ ] App Store metadata draft (name, subtitle, keywords, screenshots plan)

---

## 9) Milestone plan (suggested)

### Milestone 1: Local storage + list
- Data model, repository, list view, add draft

### Milestone 2: Scan + OCR + review
- Scanner, OCR, parsing, review screen with editable fields

### Milestone 3: Calendar + notifications
- EventKit integration, notification scheduling, settings defaults

### Milestone 4: Polish + tests + release
- Errors, loading states, accessibility, unit tests, App Store prep

---

## Out of scope (MVP)
- Backend, login, sync
- AI/cloud OCR
- Contract/Receipt automation
- Monthly budget analytics

---

# Iteration 2 (Backend + Encryption + AI Vision)

Goal: Add cloud processing and sync **without deep refactoring** of Iteration 1.
Principle: Iteration 1 must already use **protocol-based services + use cases**, so Iteration 2 becomes “swap implementations”, not rewrite screens.

---

## A) Iteration-1 guardrails to avoid refactors later (do this NOW)

### 1) Define service protocols (interfaces) in Domain/ServicesContracts/
- [ ] `OCRServiceProtocol`  
  - Iteration 1: Apple Vision on-device  
  - Iteration 2: can keep local OCR or route to backend for AI extraction
- [ ] `DocumentAnalysisServiceProtocol`  
  - Iteration 1: local invoice parsing (heuristics)  
  - Iteration 2: backend AI analysis returns structured JSON
- [ ] `FileStorageServiceProtocol`  
  - Iteration 1: local sandbox storage  
  - Iteration 2: local + optional upload token + remote references
- [ ] `SyncServiceProtocol`  
  - Iteration 1: no-op implementation  
  - Iteration 2: real sync (upload/download)
- [ ] `CryptoServiceProtocol`  
  - Iteration 1: wrapper around iOS Data Protection choices (file attributes)  
  - Iteration 2: optional extra encryption + server-side encryption

### 2) Keep ViewModels stable
- [ ] ViewModels must call **Use Cases only** (never call concrete services directly)
- [ ] Use Cases depend on **protocols**, injected via AppEnvironment

### 3) Store analysis results separately from the raw file
- [ ] Persist extracted fields into SwiftData (amount, dueDate, vendor, etc.)
- [ ] Store raw file path separately (`sourceFileURL`)
- [ ] This allows backend AI to re-analyze without changing UI

### 4) Add optional remote identifiers now (nullable fields)
Add these optional fields to `FinanceDocument` in Iteration 1:
- [ ] `remoteDocumentId: String?`
- [ ] `remoteFileId: String?`
- [ ] `analysisVersion: Int` (default 1)
- [ ] `analysisProvider: String?` (e.g. "local", "openai", "gemini")
This prevents schema pain later.

---

## B) Backend scope (Iteration 2)

### B1) Backend responsibilities
- [ ] Authenticate user (simple and production-grade)
- [ ] Receive uploads (scans/PDF)
- [ ] Store files encrypted at rest
- [ ] Run AI Vision analysis (OpenAI Vision or Google Gemini Vision)
- [ ] Return structured result (JSON)
- [ ] Sync documents (metadata + analysis results) to devices
- [ ] Optional: short retention for raw files (recommended)

### B2) Suggested backend components (conceptual)
- API (HTTP): receives metadata, returns analysis + sync data
- Storage: encrypted file store (bucket / object storage)
- Worker/Queue: processes uploads and calls AI provider
- DB: stores documents + analysis results + user account info

---

## C) Security & encryption (Iteration 2)

### C1) In transit (mandatory)
- [ ] Enforce HTTPS/TLS everywhere
- [ ] Use short-lived upload tokens (pre-signed URLs) to upload directly to storage (optional but recommended)

### C2) At rest (server-side encryption)
- [ ] Store uploaded files encrypted at rest using cloud KMS/envelope encryption
- [ ] Store only required metadata in DB (minimize sensitive fields)

### C3) Retention policy (biggest real-world win)
- [ ] Default: delete raw uploaded scans after analysis (or after X days)
- [ ] Allow “keep originals” only for paid tier (optional)
- [ ] Never log raw document text or images

### C4) Optional: client-side CryptoKit encryption (only if needed)
- [ ] Add `CryptoServiceProtocol` implementation using CryptoKit
- [ ] Encrypt file before upload
- [ ] Backend decrypts for AI processing (key management required)
Note: This increases complexity; consider enabling only if you truly need it.

---

## D) AI Vision analysis (Iteration 2)

### D1) Define a stable analysis contract (JSON)
- [ ] Create `DocumentAnalysisResult` model (shared between iOS and backend):
  - [ ] `documentType`
  - [ ] `vendorName`
  - [ ] `amount`
  - [ ] `currency`
  - [ ] `dueDate`
  - [ ] `invoiceNumber`
  - [ ] `confidence` (per field or overall)
  - [ ] `rawHints` (optional, for debugging; never store raw OCR text long-term)

### D2) Backend analysis pipeline
- [ ] Worker receives `remoteFileId`
- [ ] Downloads/decrypts file in memory
- [ ] Sends to AI provider (Vision model)
- [ ] Receives structured output (enforce JSON schema)
- [ ] Saves analysis result to DB
- [ ] Notifies client via polling endpoint or push (optional)

### D3) iOS integration strategy (no refactor)
- [ ] In `ExtractAndSuggestFieldsUseCase`, add a decision:
  - [ ] If “Cloud analysis enabled” AND user is Pro → call `DocumentAnalysisServiceProtocol` remote implementation
  - [ ] Else → use local parsing
- [ ] UI stays the same: still shows suggestions + allows manual correction

### D4) Fail-safe behavior
- [ ] If AI fails/timeouts → fallback to local OCR+heuristics
- [ ] Always allow manual edit + save

---

## E) Sync (Iteration 2)

### E1) Authentication (choose one path, keep simple)
- [ ] Sign in with Apple (recommended for iOS-first)
- [ ] Optionally email magic link later

### E2) Sync endpoints (minimum)
- [ ] `POST /documents` create/update metadata
- [ ] `GET /documents` list + incremental updates (since timestamp)
- [ ] `POST /documents/{id}/upload` get upload URL/token
- [ ] `POST /documents/{id}/analyze` trigger analysis (or auto-trigger on upload)
- [ ] `GET /documents/{id}` details + analysis result

### E3) Local mapping
- [ ] Map `FinanceDocument.remoteDocumentId` to backend id
- [ ] Conflict strategy (simple):
  - [ ] “last write wins” for MVP
  - [ ] Keep local changes if offline; sync when online

---

## F) Iteration 2 task list (deliverables)

### F1) Backend foundation
- [ ] Create API project + deploy environment
- [ ] Add auth (Sign in with Apple compatible token flow)
- [ ] Create DB schema for documents + analysis results
- [ ] Create encrypted storage bucket + access policy

### F2) Upload + storage
- [ ] Implement secure upload (direct-to-storage or via API)
- [ ] Store `remoteFileId` + retention timer
- [ ] Add deletion job according to retention policy

### F3) AI analysis
- [ ] Implement worker + queue
- [ ] Integrate AI provider (OpenAI Vision or Gemini Vision)
- [ ] Enforce JSON schema validation
- [ ] Save analysis result + confidence

### F4) iOS cloud toggle + remote analysis
- [ ] Add “Cloud analysis” setting (off by default)
- [ ] Implement `RemoteDocumentAnalysisService`
- [ ] Update `ExtractAndSuggestFieldsUseCase` to route based on setting/tier
- [ ] Add progress UI (analyzing… / fallback message)

### F5) Sync
- [ ] Implement `SyncService` (upload/download metadata)
- [ ] Background sync trigger (manual “Sync now” is enough to start)

### F6) Security review
- [ ] Verify no raw text/images in logs
- [ ] Verify encryption at rest
- [ ] Verify retention deletion runs
- [ ] Document privacy policy updates

---

## G) Out of scope (Iteration 2)
- Multi-user sharing within one company (teams)
- Advanced conflict resolution
- Full web app (only landing + optional read-only dashboard later)
