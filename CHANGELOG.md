# DuEasy Changelog

## [Unreleased] - Iteration 1 MVP

### 2026-01-30 - Initial Development

#### Added

**Milestone 1: Foundation and Data Layer** - COMPLETE
- Project structure with clean architecture (SwiftUI Views -> MVVM ViewModels -> Use Cases -> Services -> SwiftData)
- Service protocols for Iteration 2 extensibility:
  - OCRServiceProtocol
  - DocumentAnalysisServiceProtocol
  - FileStorageServiceProtocol
  - CalendarServiceProtocol
  - NotificationServiceProtocol
  - SyncServiceProtocol (no-op for Iteration 1)
  - CryptoServiceProtocol (iOS Data Protection wrapper)
- SwiftData models:
  - FinanceDocument with Iteration 2 nullable fields (remoteDocumentId, remoteFileId, analysisVersion, analysisProvider)
  - DocumentType enum (invoice, contract, receipt)
  - DocumentStatus enum (draft, scheduled, paid, archived)
  - DocumentAnalysisResult model
- SwiftDataDocumentRepository with full CRUD and query operations
- Design System:
  - Spacing scale (4pt grid)
  - Typography tokens (SF Pro, Dynamic Type)
  - Color tokens (semantic + glass variants)
  - Elevation system
  - Card component (glass/solid modes with accessibility fallbacks)
  - DocumentRow, StatusBadge, PrimaryButton, EmptyStateView, LoadingView, ErrorBanner
- AppEnvironment dependency container with use case factory methods
- SettingsManager for local settings persistence

**Milestone 2: Scanning and OCR Pipeline** - COMPLETE
- LocalFileStorageService with iOS Data Protection (NSFileProtectionComplete)
- AppleVisionOCRService with multi-language support (Polish + English)
- LocalInvoiceParsingService with heuristic parsing:
  - Date extraction (dd.mm.yyyy, yyyy-mm-dd formats)
  - Keyword proximity detection for due dates
  - Amount extraction with currency detection (PLN, EUR, USD)
  - Vendor name and invoice number extraction
- DocumentScannerView wrapping VisionKit VNDocumentCameraViewController
- Use Cases:
  - CreateDocumentUseCase
  - ScanAndAttachFileUseCase
  - ExtractAndSuggestFieldsUseCase

**Milestone 3: Calendar and Notifications** - COMPLETE
- EventKitCalendarService with full event management
- LocalNotificationService with reminder scheduling
- Use Cases:
  - FinalizeInvoiceUseCase (validates, creates calendar event, schedules notifications)
  - MarkAsPaidUseCase (cancels future notifications)
  - DeleteDocumentUseCase (full cleanup of files, events, notifications)
  - UpdateDocumentUseCase (syncs calendar and notifications)

**Milestone 4: Polish and Testing** - IN PROGRESS
- Error handling with AppError types and user-friendly messages
- Validation rules for amount, due date, vendor name
- Accessibility support:
  - Dynamic Type
  - Reduce Motion support
  - Reduce Transparency support (solid fallbacks)
  - Accessibility labels and hints
- Unit tests:
  - InvoiceParsingServiceTests
  - NotificationSchedulingTests
  - ValidationTests

**UI Screens**
- MainTabView (Documents + Settings tabs)
- DocumentListView with filtering and search
- AddDocumentView with document type selection
- DocumentScannerView (VisionKit integration)
- DocumentReviewView with OCR extraction and field editing
- DocumentDetailView with actions (Edit, Mark Paid, Delete)
- SettingsView with reminder and calendar preferences
- OnboardingView with value proposition

#### Architecture Decisions

| Decision | Rationale | Trade-offs |
|----------|-----------|------------|
| iOS 17+ target | SwiftData availability + modern APIs | Excludes iOS 16 users |
| Contract/Receipt as "Coming soon" | Focus MVP on Invoice flow | Users cannot scan other document types |
| UserDefaults for settings | Simplicity for key-value pairs | Could migrate to SwiftData later |
| Local heuristic parsing | No backend dependency for MVP | Less accurate than AI analysis |
| Protocol-based services | Clean swap for Iteration 2 backends | Slight abstraction overhead |

#### Iteration 2 Preparation
- All services are protocol-based for easy backend swap
- FinanceDocument includes nullable remote fields
- DocumentAnalysisResult designed for JSON serialization
- SyncServiceProtocol stub ready for implementation
- CryptoServiceProtocol ready for CryptoKit enhancement

---

## Future Backlog (Iteration 2+)

- [ ] Backend authentication (Sign in with Apple)
- [ ] Cloud document sync
- [ ] AI Vision analysis (OpenAI Vision / Gemini)
- [ ] Server-side encryption
- [ ] Remote document storage
- [ ] Contract/Receipt automation
- [ ] Monthly budget analytics
- [ ] Multi-device sync
- [ ] Web dashboard (read-only)
- [ ] PDF import support
- [ ] Receipt scanning with merchant detection
- [ ] Recurring invoice detection
