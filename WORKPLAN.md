# DuEasy MVP Work Plan

## Overview

**Product**: DuEasy - Document scanning and deadline management iOS application
**Iteration 1**: Fully local MVP with document scanning, field extraction, calendar integration, and notifications
**Iteration 2**: Backend integration with encryption, AI vision processing, and cloud sync (minimal refactoring)

**Architecture**: SwiftUI Views -> MVVM ViewModels -> Use Cases -> Protocol-based Services/Repositories -> SwiftData

---

## Milestones

### Milestone 1: Foundation and Data Layer
**Goal**: Project setup, data model, repository, design system, basic list UI
**Duration**: Core infrastructure enabling all subsequent work

### Milestone 2: Scanning and OCR Pipeline
**Goal**: VisionKit scanner, OCR service, invoice parsing, file storage
**Duration**: Complete scan-to-extraction pipeline

### Milestone 3: Calendar and Notifications
**Goal**: EventKit integration, notification scheduling, settings
**Duration**: Full automation of deadline management

### Milestone 4: Polish, Testing, and Release
**Goal**: Error handling, accessibility, tests, App Store preparation
**Duration**: Production-ready release

---

## Milestone 1: Foundation and Data Layer

### M1.1 Project Setup
**Section**: Project setup (Section 1)
**Acceptance Criteria**:
- Xcode project created with iOS 17+ target
- Bundle ID and signing configured
- Info.plist with all required usage strings (Camera, Calendar, Notifications)
- Folder structure matches architecture (App/, Features/, Domain/, Data/, Services/, Shared/)
- AppEnvironment dependency container created

### M1.2 Service Protocols (Iteration 2 Guardrails)
**Section**: Iteration 2 guardrails (Section A)
**Acceptance Criteria**:
- OCRServiceProtocol defined
- DocumentAnalysisServiceProtocol defined
- FileStorageServiceProtocol defined
- CalendarServiceProtocol defined
- NotificationServiceProtocol defined
- SyncServiceProtocol defined (no-op for Iteration 1)
- CryptoServiceProtocol defined (iOS Data Protection wrapper)
- All protocols in Domain/Contracts/

### M1.3 Data Model (SwiftData)
**Section**: Data model (Section 2)
**Acceptance Criteria**:
- DocumentType enum: invoice, contract, receipt
- DocumentStatus enum: draft, scheduled, paid, archived
- FinanceDocument @Model with all fields including Iteration 2 nullable fields
- DocumentAnalysisResult model for structured extraction results
- ModelContainer configured
- Migration/versioning convention documented

### M1.4 Repository Layer
**Section**: Data layer (Section 0)
**Acceptance Criteria**:
- DocumentRepositoryProtocol defined
- SwiftDataDocumentRepository implementation
- CRUD operations: create, read, update, delete
- Query methods: fetchAll, fetchByStatus, search
- Error handling with typed errors

### M1.5 Design System
**Section**: UI foundations (Section 0)
**Acceptance Criteria**:
- Spacing scale (4pt grid)
- Typography tokens (SF Pro, Dynamic Type)
- Color tokens (semantic + glass variants)
- Elevation system (shadows)
- Card component (glass/solid modes)
- DocumentRow component
- StatusBadge component
- PrimaryButton component
- Environment-driven accessibility fallbacks

### M1.6 Document List Screen
**Section**: UI Screens - Document List (Section 5.2)
**Acceptance Criteria**:
- DocumentListView with segmented filter (Pending/Scheduled/Paid/All)
- Search functionality (vendor/title)
- Empty state
- DocumentListViewModel fetching from repository
- Delete action working
- Pull-to-refresh (even if local-only)

### M1.7 Basic Navigation Shell
**Section**: UI Screens (Section 5)
**Acceptance Criteria**:
- NavigationStack setup
- Tab bar or navigation pattern for Home/Settings
- Onboarding flow shell (can be placeholder)

---

## Milestone 2: Scanning and OCR Pipeline

### M2.1 FileStorageService
**Section**: Services - FileStorageService (Section 3.1)
**Acceptance Criteria**:
- Protocol implementation
- Save document files (images/PDF) to app sandbox
- Load document files
- Delete document files
- iOS file protection enabled (NSFileProtectionComplete)
- Typed error handling

### M2.2 ScannerService (VisionKit)
**Section**: Services - ScannerService (Section 3.2)
**Acceptance Criteria**:
- VisionKit document camera integration
- High-quality image capture
- Normalized output format for OCR (UIImage array)
- Error handling for camera unavailable/permission denied

### M2.3 OCRService (Apple Vision)
**Section**: Services - OCRService (Section 3.3)
**Acceptance Criteria**:
- recognizeText(images) -> String implementation
- Multi-language support (Polish + English)
- Quality/confidence handling
- Warning surfacing for low-confidence results

### M2.4 InvoiceParsingService
**Section**: Services - InvoiceParsingService (Section 3.4)
**Acceptance Criteria**:
- parseInvoice(text) -> ParsedInvoice implementation
- Date format parsing (dd.mm.yyyy, yyyy-mm-dd)
- Keyword proximity detection (Termin platnosci, Due date, etc.)
- Amount extraction with currency detection (PLN, EUR, zl)
- Vendor name extraction
- Invoice number extraction
- All fields are suggestions (manual correction always allowed)

### M2.5 Use Cases (Scan Flow)
**Section**: Domain Use Cases (Section 4)
**Acceptance Criteria**:
- CreateDocumentUseCase: create draft document
- ScanAndAttachFileUseCase: scan, save, attach
- ExtractAndSuggestFieldsUseCase: OCR + parse + return suggestions

### M2.6 Add Document Screen
**Section**: UI Screens - Add Document (Section 5.3)
**Acceptance Criteria**:
- AddDocumentView with DocumentType picker
- Invoice enabled, Contract/Receipt disabled or "Save only"
- Scan button launching VisionKit
- Import PDF option (optional for MVP)
- AddDocumentViewModel creating draft and launching scanner

### M2.7 Document Review Screen
**Section**: UI Screens - Review & Edit (Section 5.4)
**Acceptance Criteria**:
- DocumentReviewView with image preview
- Editable fields: vendor, amount, dueDate, invoiceNumber
- Reminder offsets UI (toggles)
- "Save & Add to Calendar" CTA
- DocumentReviewViewModel running OCR/parsing async
- Loading states during processing
- Validation before save

---

## Milestone 3: Calendar and Notifications

### M3.1 CalendarService (EventKit)
**Section**: Services - CalendarService (Section 3.5)
**Acceptance Criteria**:
- Calendar access request with user messaging
- Add event to calendar
- Update event when document changes
- Remove event on delete
- Store calendarEventId in document
- Optional dedicated "Invoices" calendar creation

### M3.2 NotificationService
**Section**: Services - NotificationService (Section 3.6)
**Acceptance Criteria**:
- Permission request
- Schedule notifications based on dueDate + offsets
- Update notifications when dueDate changes
- Cancel notifications on delete
- Respect global defaults from settings

### M3.3 FinalizeInvoiceUseCase
**Section**: Domain Use Cases (Section 4)
**Acceptance Criteria**:
- Validate fields (amount > 0, dueDate >= today with warning override)
- Persist final values
- Add/update calendar event
- Schedule notifications
- Update status to scheduled

### M3.4 MarkAsPaidUseCase
**Section**: Domain Use Cases (Section 4)
**Acceptance Criteria**:
- Set status to paid
- Cancel future notifications (configurable)
- Keep calendar event as record

### M3.5 DeleteDocumentUseCase
**Section**: Domain Use Cases (Section 4)
**Acceptance Criteria**:
- Remove calendar event
- Cancel notifications
- Delete stored file
- Delete SwiftData record
- Proper cleanup on partial failures

### M3.6 Document Detail Screen
**Section**: UI Screens - Document Details (Section 5.5)
**Acceptance Criteria**:
- DocumentDetailView showing all fields + status
- Edit action
- Mark Paid action
- Remove from Calendar action
- Delete action with confirmation
- DocumentDetailViewModel keeping calendar/notifications in sync

### M3.7 Settings Screen
**Section**: UI Screens - Settings (Section 5.6)
**Acceptance Criteria**:
- Default reminder offsets configuration
- Calendar selection
- Help/contact info
- SettingsViewModel persisting settings locally

### M3.8 Permissions and Onboarding
**Section**: UI Screens - Onboarding (Section 5.1)
**Acceptance Criteria**:
- OnboardingView with value proposition
- PermissionsViewModel requesting camera, calendar, notifications
- Rationale text before system prompts
- Graceful degradation if permissions denied

---

## Milestone 4: Polish, Testing, and Release

### M4.1 Error Handling
**Section**: Services - Error handling (Section 3.7)
**Acceptance Criteria**:
- AppError types per service
- OSLog logging (no sensitive data)
- User-friendly error messages
- Retry options where appropriate
- Banner/alert error presentation

### M4.2 Validation Rules
**Section**: Validation rules (Section 6)
**Acceptance Criteria**:
- Amount > 0 validation
- DueDate >= today validation with warning override
- Vendor/title empty warning
- Calendar permission denied handling (save without event)

### M4.3 Accessibility
**Section**: UI foundations (Section 0)
**Acceptance Criteria**:
- Dynamic Type support
- Reduce Motion support (disable animations)
- Reduce Transparency support (solid fallbacks)
- Increase Contrast support
- Accessibility labels for all controls
- VoiceOver testing

### M4.4 Unit Tests
**Section**: Testing - Unit tests (Section 7)
**Acceptance Criteria**:
- InvoiceParsingService tests (date formats, amounts, keywords)
- Notification scheduling logic tests
- Date offset calculations tests
- Validation logic tests

### M4.5 Integration Tests
**Section**: Testing - Integration tests (Section 7)
**Acceptance Criteria**:
- Create document -> attach file -> finalize -> verify eventId
- Mock services via protocols
- Full flow testing

### M4.6 Manual Test Checklist Verification
**Section**: Testing - Manual checklist (Section 7)
**Acceptance Criteria**:
- Scan sharp invoice -> OCR suggestions ok
- OCR fails -> manual entry works
- Save & add to calendar works
- Notifications fire at expected times
- Edit due date updates calendar + notifications
- Delete removes everything cleanly

### M4.7 Release Preparation
**Section**: Release readiness (Section 8)
**Acceptance Criteria**:
- App icon
- Basic branding
- Privacy notes (local processing)
- In-app FAQ
- Crash-free on real device
- App Store metadata draft

---

## Critical Path Verification (After Each Milestone)

Test this flow end-to-end:
1. Scan document
2. OCR extracts text
3. Review extracted fields (edit if needed)
4. Save document
5. Calendar event created
6. Notifications scheduled
7. Edit/Update document (calendar/notifications sync)
8. Delete document (full cleanup)

---

## Future Backlog (Iteration 2+)

- Backend authentication (Sign in with Apple)
- Cloud document sync
- AI Vision analysis (OpenAI Vision / Gemini)
- Server-side encryption
- Remote document storage
- Contract/Receipt automation
- Monthly budget analytics
- Multi-device sync
- Web dashboard (read-only)

---

## Decisions Log

| Date | Decision | Rationale | Trade-offs |
|------|----------|-----------|------------|
| 2026-01-30 | Start with iOS 17+ target | Balances SwiftData availability with device coverage | Excludes iOS 16 users |
| 2026-01-30 | Contract/Receipt as "Coming soon" disabled | Focus MVP scope on Invoice flow | Users cannot scan other document types |
| 2026-01-30 | Use UserDefaults for settings, SwiftData for documents | Simplicity for key-value settings | Could migrate to SwiftData later if needed |

---

## Changelog

### 2026-01-30
- Initial work plan created from D2_MVP_tasks_v3_with_UI_LiquidGlass.md specification
- Defined 4 milestones with detailed tasks and acceptance criteria
- Established critical path verification checklist
- Created future backlog for Iteration 2+
