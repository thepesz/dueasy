import Foundation
import Observation
import SwiftUI
import os.log

/// ViewModel for the document list screen.
/// Manages document fetching, filtering, search, and recurring payment auto-detection.
@MainActor
@Observable
final class DocumentListViewModel {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "DocumentList")

    // MARK: - State

    var documents: [FinanceDocument] = []
    var selectedFilter: DocumentFilter = .all
    var searchText: String = ""
    var isLoading: Bool = false
    var error: AppError?
    var statusCounts: [DocumentStatus: Int] = [:]

    /// Recurring payment suggestions detected by auto-detection.
    /// Shown as cards at the top of the document list.
    var suggestedCandidates: [RecurringCandidate] = []

    /// Whether auto-detection is currently running
    var isDetectionRunning: Bool = false

    // MARK: - Dependencies

    private let fetchDocumentsUseCase: FetchDocumentsUseCase
    private let countDocumentsUseCase: CountDocumentsByStatusUseCase
    private let deleteUseCase: DeleteDocumentUseCase
    private let detectCandidatesUseCase: DetectRecurringCandidatesUseCase?
    private let schedulerService: RecurringSchedulerServiceProtocol?
    private let linkExistingDocumentsUseCase: LinkExistingDocumentsUseCase?
    private let documentRepository: DocumentRepositoryProtocol?

    // MARK: - Computed Properties

    var filteredDocuments: [FinanceDocument] {
        var result = documents

        // Apply status filter
        switch selectedFilter {
        case .all:
            break
        case .pending:
            result = result.filter { $0.status == .draft }
        case .scheduled:
            result = result.filter { $0.status == .scheduled }
        case .paid:
            result = result.filter { $0.status == .paid }
        case .overdue:
            result = result.filter { $0.isOverdue }
        }

        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { document in
                document.title.lowercased().contains(query) ||
                (document.documentNumber?.lowercased().contains(query) ?? false) ||
                (document.notes?.lowercased().contains(query) ?? false)
            }
        }

        return result
    }

    var hasDocuments: Bool {
        !documents.isEmpty
    }

    var hasFilteredDocuments: Bool {
        !filteredDocuments.isEmpty
    }

    var overdueCount: Int {
        documents.filter { $0.isOverdue }.count
    }

    /// Whether there are recurring suggestions to show
    var hasSuggestions: Bool {
        !suggestedCandidates.isEmpty
    }

    /// Document pending deletion (triggers deletion flow)
    var documentPendingDeletion: FinanceDocument?

    /// Step 1: Whether to show initial delete confirmation alert
    var showDeleteConfirmation: Bool = false

    /// Step 2: Whether to show recurring deletion sheet (only if document is linked to recurring)
    var showRecurringDeletionSheet: Bool = false

    // MARK: - Initialization

    init(
        fetchDocumentsUseCase: FetchDocumentsUseCase,
        countDocumentsUseCase: CountDocumentsByStatusUseCase,
        deleteUseCase: DeleteDocumentUseCase,
        detectCandidatesUseCase: DetectRecurringCandidatesUseCase? = nil,
        schedulerService: RecurringSchedulerServiceProtocol? = nil,
        linkExistingDocumentsUseCase: LinkExistingDocumentsUseCase? = nil,
        documentRepository: DocumentRepositoryProtocol? = nil
    ) {
        self.fetchDocumentsUseCase = fetchDocumentsUseCase
        self.countDocumentsUseCase = countDocumentsUseCase
        self.deleteUseCase = deleteUseCase
        self.detectCandidatesUseCase = detectCandidatesUseCase
        self.schedulerService = schedulerService
        self.linkExistingDocumentsUseCase = linkExistingDocumentsUseCase
        self.documentRepository = documentRepository
    }

    // MARK: - Actions

    func loadDocuments() async {
        print("🔵 LOAD_DOCUMENTS: Starting...")
        isLoading = true
        error = nil

        do {
            // Proper MVVM flow: ViewModel → UseCase → Repository
            print("🔵 LOAD_DOCUMENTS: Fetching documents from use case...")
            documents = try await fetchDocumentsUseCase.execute()
            print("🔵 LOAD_DOCUMENTS: Fetched \(documents.count) documents")

            print("🔵 LOAD_DOCUMENTS: Counting documents by status...")
            statusCounts = try await countDocumentsUseCase.executeAll()
            print("🔵 LOAD_DOCUMENTS: Status counts: \(statusCounts)")

            // CRITICAL: Run recurring payment auto-detection after loading documents.
            // This analyzes vendor patterns and generates suggestions for recurring payments.
            print("🔵 LOAD_DOCUMENTS: Running recurring detection...")
            await runRecurringDetection()
            print("🔵 LOAD_DOCUMENTS: Recurring detection complete")

        } catch let appError as AppError {
            print("🔵 LOAD_DOCUMENTS: Error (AppError): \(appError)")
            error = appError
        } catch {
            print("🔵 LOAD_DOCUMENTS: Error (Unknown): \(error.localizedDescription)")
            self.error = .repositoryFetchFailed(error.localizedDescription)
        }

        isLoading = false
        print("🔵 LOAD_DOCUMENTS: Complete. Final document count: \(documents.count)")
    }

    // MARK: - Recurring Payment Auto-Detection

    /// Runs the recurring payment auto-detection analysis.
    /// Called automatically after loading documents.
    private func runRecurringDetection() async {
        guard let detectUseCase = detectCandidatesUseCase else {
            logger.debug("Auto-detection skipped: DetectRecurringCandidatesUseCase not provided")
            return
        }

        guard !isDetectionRunning else {
            logger.debug("Auto-detection already running, skipping")
            return
        }

        isDetectionRunning = true
        logger.info("Starting recurring payment auto-detection")

        do {
            let candidates = try await detectUseCase.execute()
            suggestedCandidates = candidates
            logger.info("Auto-detection complete: found \(candidates.count) suggestions")

            for candidate in candidates {
                logger.info("  - \(candidate.vendorDisplayName): confidence=\(candidate.confidenceScore), docs=\(candidate.documentCount)")
            }
        } catch {
            logger.error("Auto-detection failed: \(error.localizedDescription)")
            // Don't show error to user - auto-detection is a background feature
        }

        isDetectionRunning = false
    }

    /// Accepts a recurring suggestion and creates a template.
    /// - Parameters:
    ///   - candidate: The candidate to accept
    ///   - reminderOffsets: Days before due date to send reminders (default: [7, 1, 0])
    ///   - durationMonths: How many months ahead to generate instances (default: 12)
    func acceptSuggestion(
        _ candidate: RecurringCandidate,
        reminderOffsets: [Int] = [7, 1, 0],
        durationMonths: Int = 12
    ) async {
        guard let detectUseCase = detectCandidatesUseCase,
              let scheduler = schedulerService else {
            logger.error("Cannot accept suggestion: missing dependencies")
            return
        }

        logger.info("=== ACCEPT SUGGESTION START ===")
        logger.info("Vendor: \(candidate.vendorDisplayName)")
        logger.info("Fingerprint: \(candidate.vendorFingerprint)")
        logger.info("Document Count: \(candidate.documentCount)")
        logger.info("Reminders: \(reminderOffsets)")
        logger.info("Duration: \(durationMonths) months")

        do {
            // Step 1: Create template from candidate
            logger.info("STEP 1: Creating template from candidate...")
            let template = try await detectUseCase.acceptCandidate(candidate, reminderOffsets: reminderOffsets)
            logger.info("Template created: id=\(template.id), vendorFingerprint=\(template.vendorFingerprint)")

            // Step 2: Generate instances for the new template
            logger.info("STEP 2: Generating instances...")
            let instances = try await scheduler.generateInstances(for: template, monthsAhead: durationMonths)
            logger.info("Generated \(instances.count) recurring instances")

            // Step 3: Link existing documents to the generated instances
            logger.info("STEP 3: Linking existing documents...")
            if let linkUseCase = linkExistingDocumentsUseCase {
                logger.info("LinkExistingDocumentsUseCase is available, executing...")
                let linkedCount = try await linkUseCase.execute(template: template, toleranceDays: template.toleranceDays)
                logger.info("LINK RESULT: \(linkedCount) documents linked to template")
            } else {
                logger.error("LinkExistingDocumentsUseCase is NIL - documents will NOT be linked!")
            }

            // Remove from suggestions
            suggestedCandidates.removeAll { $0.id == candidate.id }
            logger.info("Removed candidate from suggestions")

            // Refresh documents to show updated recurring linkage
            logger.info("STEP 4: Refreshing documents...")
            await loadDocuments()
            logger.info("Documents refreshed")

            logger.info("=== ACCEPT SUGGESTION COMPLETE ===")

        } catch {
            logger.error("ACCEPT SUGGESTION FAILED: \(error.localizedDescription)")
            self.error = .repositorySaveFailed(error.localizedDescription)
        }
    }

    /// Dismisses a recurring suggestion permanently.
    /// - Parameter candidate: The candidate to dismiss
    func dismissSuggestion(_ candidate: RecurringCandidate) async {
        guard let detectUseCase = detectCandidatesUseCase else {
            logger.error("Cannot dismiss suggestion: missing dependencies")
            return
        }

        logger.info("Dismissing recurring suggestion: \(candidate.vendorDisplayName)")

        do {
            try await detectUseCase.dismissCandidate(candidate)
            suggestedCandidates.removeAll { $0.id == candidate.id }
        } catch {
            logger.error("Failed to dismiss suggestion: \(error.localizedDescription)")
        }
    }

    /// Snoozes a recurring suggestion (will reappear later).
    /// - Parameter candidate: The candidate to snooze
    func snoozeSuggestion(_ candidate: RecurringCandidate) async {
        guard let detectUseCase = detectCandidatesUseCase else {
            logger.error("Cannot snooze suggestion: missing dependencies")
            return
        }

        logger.info("Snoozing recurring suggestion: \(candidate.vendorDisplayName)")

        do {
            try await detectUseCase.snoozeCandidate(candidate)
            suggestedCandidates.removeAll { $0.id == candidate.id }
        } catch {
            logger.error("Failed to snooze suggestion: \(error.localizedDescription)")
        }
    }

    /// Step 1: Initiates deletion flow by showing initial confirmation alert.
    /// This matches iOS Calendar's two-step deletion UX.
    func deleteDocument(_ document: FinanceDocument) async {
        logger.info("=== DELETE DOCUMENT - STEP 1 ===")
        logger.info("Document ID: \(document.id)")
        logger.info("Document Title: \(document.title)")

        // Always show initial confirmation first (like iOS Calendar)
        documentPendingDeletion = document
        showDeleteConfirmation = true

        logger.info("Showing initial delete confirmation alert")
    }

    /// Step 2: Called after user confirms initial deletion.
    /// If document is linked to recurring, shows additional options sheet.
    /// If not recurring, executes standard deletion immediately.
    func confirmDeleteDocument() async {
        guard let document = documentPendingDeletion else {
            logger.error("confirmDeleteDocument called but no document pending")
            return
        }

        logger.info("=== DELETE DOCUMENT - STEP 2 ===")
        logger.info("Document ID: \(document.id)")

        // CRITICAL FIX: Fetch fresh document data from the database before checking recurring status.
        // SwiftData caches objects in memory, and after batch operations like linking documents
        // to recurring templates, the in-memory objects may have stale values.
        // Without this fresh fetch, document.recurringInstanceId might show as nil even though
        // the database has the correct linked value.
        var documentToCheck = document
        if let repository = documentRepository {
            logger.info("FETCH_FRESH: Getting fresh document from database before checking recurring status...")
            do {
                if let freshDocument = try await repository.fetchFresh(documentId: document.id) {
                    documentToCheck = freshDocument
                    // Update the pending deletion reference to use fresh data
                    documentPendingDeletion = freshDocument
                    logger.info("FETCH_FRESH: Got fresh document data")
                } else {
                    logger.warning("FETCH_FRESH: Document not found in database - using cached version")
                }
            } catch {
                logger.error("FETCH_FRESH: Failed to fetch fresh document: \(error.localizedDescription) - using cached version")
            }
        } else {
            logger.warning("FETCH_FRESH: No repository available for fresh fetch - using cached values")
        }

        logger.info("recurringInstanceId: \(documentToCheck.recurringInstanceId?.uuidString ?? "nil")")
        logger.info("recurringTemplateId: \(documentToCheck.recurringTemplateId?.uuidString ?? "nil")")

        // Check if document is linked to recurring payment
        let hasInstanceId = documentToCheck.recurringInstanceId != nil
        let hasTemplateId = documentToCheck.recurringTemplateId != nil
        let isLinkedToRecurring = hasInstanceId || hasTemplateId

        logger.info("isLinkedToRecurring: \(isLinkedToRecurring)")

        if isLinkedToRecurring {
            // Document is linked to recurring payment - show step 2 options
            logger.info("DECISION: Document IS linked to recurring - showing options sheet")
            showRecurringDeletionSheet = true
        } else {
            // Not recurring - execute standard deletion immediately
            logger.info("DECISION: Document is NOT linked to recurring - executing standard deletion")
            await executeStandardDeletion(documentToCheck)
            documentPendingDeletion = nil
        }
    }

    /// Cancels the deletion flow and clears pending state.
    func cancelDeleteDocument() {
        logger.info("Delete cancelled by user")
        documentPendingDeletion = nil
        showDeleteConfirmation = false
        showRecurringDeletionSheet = false
    }

    /// Executes standard deletion without recurring checks.
    /// Called after recurring deletion modal completes.
    func executeStandardDeletion(_ document: FinanceDocument) async {
        logger.info("🗑️ DELETE: Executing standard deletion for document \(document.id)")
        do {
            try await deleteUseCase.execute(documentId: document.id)
            // Refresh list after deletion
            await loadDocuments()
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .repositoryDeleteFailed(error.localizedDescription)
        }
    }

    func clearError() {
        error = nil
    }

    func setFilter(_ filter: DocumentFilter) {
        selectedFilter = filter
    }
}

// MARK: - Document Filter

enum DocumentFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case scheduled
    case paid
    case overdue

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:
            return L10n.Filters.all.localized
        case .pending:
            return L10n.Filters.pending.localized
        case .scheduled:
            return L10n.Filters.scheduled.localized
        case .paid:
            return L10n.Filters.paid.localized
        case .overdue:
            return L10n.Filters.overdue.localized
        }
    }

    var iconName: String {
        switch self {
        case .all:
            return "doc.on.doc"
        case .pending:
            return "doc.badge.ellipsis"
        case .scheduled:
            return "calendar.badge.clock"
        case .paid:
            return "checkmark.circle"
        case .overdue:
            return "exclamationmark.triangle"
        }
    }
}
