import Foundation
import Observation
import SwiftUI
import Combine
import os.log

/// ViewModel for the document list screen.
/// Manages document fetching, filtering, search, and recurring payment auto-detection.
///
/// Performance Optimization: Filtering and search are performed at the repository/database level
/// rather than in-memory. This scales efficiently with thousands of documents.
@MainActor
@Observable
final class DocumentListViewModel {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "DocumentList")

    // MARK: - State

    /// Documents currently loaded (already filtered by repository)
    var documents: [FinanceDocument] = []

    /// Current filter selection
    private(set) var selectedFilter: DocumentFilter = .all

    /// Current search text (debounced before triggering fetch)
    var searchText: String = "" {
        didSet {
            searchTextSubject.send(searchText)
        }
    }

    var isLoading: Bool = false
    var error: AppError?
    var statusCounts: [DocumentStatus: Int] = [:]

    /// Total document count (for "All" filter badge, fetched separately)
    var totalDocumentCount: Int = 0

    /// Overdue count (fetched separately for badge display)
    private(set) var overdueCount: Int = 0

    /// Recurring payment suggestions detected by auto-detection.
    /// Shown as cards at the top of the document list.
    var suggestedCandidates: [RecurringCandidate] = []

    /// Whether auto-detection is currently running
    var isDetectionRunning: Bool = false

    // MARK: - Search Debouncing

    /// Subject for debouncing search input
    private let searchTextSubject = PassthroughSubject<String, Never>()

    /// Cancellable for search debounce subscription
    private var searchDebounceSubscription: AnyCancellable?

    /// Debounce interval for search (milliseconds)
    private static let searchDebounceInterval: Int = 300

    // MARK: - Recurring Detection Background Processing

    /// Task handle for background recurring detection (allows cancellation)
    private var detectionTask: Task<Void, Never>?

    /// Debounce delay before starting recurring detection (seconds)
    /// Prevents rapid refreshes from triggering multiple expensive detection runs
    private static let detectionDelay: TimeInterval = 0.5

    // MARK: - Dependencies

    private let fetchDocumentsUseCase: FetchDocumentsUseCase
    private let countDocumentsUseCase: CountDocumentsByStatusUseCase
    private let deleteUseCase: DeleteDocumentUseCase
    private let detectCandidatesUseCase: DetectRecurringCandidatesUseCase?
    private let schedulerService: RecurringSchedulerServiceProtocol?
    private let linkExistingDocumentsUseCase: LinkExistingDocumentsUseCase?
    private let documentRepository: DocumentRepositoryProtocol?

    // MARK: - Computed Properties

    /// Returns the currently loaded documents.
    /// Since filtering is now done at the repository level, this simply returns the documents array.
    /// Kept for backward compatibility with existing views.
    var filteredDocuments: [FinanceDocument] {
        documents
    }

    /// Whether there are any documents in the system (ignoring current filter).
    /// Uses totalDocumentCount which is fetched separately.
    var hasDocuments: Bool {
        totalDocumentCount > 0
    }

    /// Whether the current filtered result has documents
    var hasFilteredDocuments: Bool {
        !documents.isEmpty
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

        setupSearchDebounce()
    }

    // MARK: - Search Debouncing Setup

    /// Sets up debounced search to avoid excessive database queries while typing
    private func setupSearchDebounce() {
        searchDebounceSubscription = searchTextSubject
            .debounce(for: .milliseconds(Self.searchDebounceInterval), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.fetchFilteredDocuments()
                }
            }
    }

    // MARK: - Actions

    /// Loads documents with current filter and search state.
    /// This is the main entry point for initial load and refresh.
    func loadDocuments() async {
        logger.debug("LOAD_DOCUMENTS: Starting with filter=\(self.selectedFilter.rawValue), search='\(self.searchText)'")
        isLoading = true
        error = nil

        do {
            // Fetch filtered documents from repository (database-level filtering)
            await fetchFilteredDocuments()

            // Fetch status counts for filter badges
            logger.debug("LOAD_DOCUMENTS: Counting documents by status...")
            statusCounts = try await countDocumentsUseCase.executeAll()
            logger.debug("LOAD_DOCUMENTS: Status counts: \(self.statusCounts)")

            // Calculate total and overdue counts for UI badges
            totalDocumentCount = statusCounts.values.reduce(0, +)
            overdueCount = try await countDocumentsUseCase.countOverdue()

            // Run recurring payment auto-detection in background after loading documents
            // This keeps UI responsive while detection analyzes document patterns
            logger.debug("LOAD_DOCUMENTS: Scheduling background recurring detection...")
            scheduleBackgroundDetection()

        } catch let appError as AppError {
            logger.error("LOAD_DOCUMENTS: Error (AppError): \(appError)")
            error = appError
        } catch {
            logger.error("LOAD_DOCUMENTS: Error (Unknown): \(error.localizedDescription)")
            self.error = .repositoryFetchFailed(error.localizedDescription)
        }

        isLoading = false
        logger.debug("LOAD_DOCUMENTS: Complete. Filtered document count: \(self.documents.count)")
    }

    /// Fetches documents with current filter and search state.
    /// Called by loadDocuments() and search debounce.
    private func fetchFilteredDocuments() async {
        do {
            // Normalize search query: empty string becomes nil for repository
            let searchQuery: String? = searchText.isEmpty ? nil : searchText

            // Use optimized database-level filtering
            documents = try await fetchDocumentsUseCase.execute(
                filter: selectedFilter,
                searchQuery: searchQuery
            )

            logger.debug("FETCH_FILTERED: Fetched \(self.documents.count) documents for filter=\(self.selectedFilter.rawValue), search='\(searchQuery ?? "")'")
        } catch {
            logger.error("FETCH_FILTERED: Error: \(error.localizedDescription)")
            // Don't overwrite existing documents on filter error
        }
    }

    // MARK: - Recurring Payment Auto-Detection (Background Processing)

    /// Schedules recurring detection to run in the background after a brief delay.
    /// This keeps the UI responsive during document list refresh.
    ///
    /// **Performance Optimization:**
    /// - Cancels any pending detection task (handles rapid refresh scenarios)
    /// - Waits for debounce delay to avoid redundant work
    /// - Runs heavy detection work on background thread via Task.detached
    /// - Posts results back to MainActor when complete
    private func scheduleBackgroundDetection() {
        // Cancel any pending detection to handle rapid refreshes
        detectionTask?.cancel()

        // Capture weak self to avoid retain cycles
        detectionTask = Task.detached { [weak self] in
            // Wait for debounce delay to coalesce rapid refreshes
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.detectionDelay * 1_000_000_000))
            } catch {
                // Task was cancelled during sleep - exit early
                return
            }

            // Check cancellation before starting expensive work
            guard !Task.isCancelled else { return }

            // Run detection on background thread, post results to main
            await self?.runRecurringDetectionAsync()
        }
    }

    /// Runs recurring detection asynchronously on a background thread.
    /// Results are posted back to the MainActor when complete.
    ///
    /// This method is designed to be called from Task.detached context.
    private func runRecurringDetectionAsync() async {
        guard let detectUseCase = detectCandidatesUseCase else {
            await MainActor.run {
                logger.debug("Auto-detection skipped: DetectRecurringCandidatesUseCase not provided")
            }
            return
        }

        // Check if detection is already running (thread-safe check on main)
        let shouldSkip = await MainActor.run { () -> Bool in
            if isDetectionRunning {
                logger.debug("Auto-detection already running, skipping")
                return true
            }
            isDetectionRunning = true
            logger.info("Starting background recurring payment auto-detection")
            return false
        }

        guard !shouldSkip else { return }

        do {
            // Heavy work runs off main thread
            let candidates = try await detectUseCase.execute()

            // Check cancellation before posting results
            guard !Task.isCancelled else {
                await MainActor.run {
                    isDetectionRunning = false
                    logger.debug("Auto-detection cancelled before posting results")
                }
                return
            }

            // Post results back to main thread
            await MainActor.run {
                suggestedCandidates = candidates
                isDetectionRunning = false
                logger.info("Background auto-detection complete: found \(candidates.count) suggestions")

                // PRIVACY: Log only metrics, not vendor names
                for candidate in candidates {
                    logger.info("  - Candidate: \(PrivacyLogger.candidateMetrics(confidence: candidate.confidenceScore, documentCount: candidate.documentCount))")
                }
            }
        } catch {
            await MainActor.run {
                isDetectionRunning = false
                logger.error("Background auto-detection failed: \(error.localizedDescription)")
                // Don't show error to user - auto-detection is a background feature
            }
        }
    }

    /// Cancels any pending background detection task.
    /// Called during deinitialization and when explicitly needed.
    func cancelPendingDetection() {
        detectionTask?.cancel()
        detectionTask = nil
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

        // PRIVACY: Log only metrics, not vendor names or fingerprints
        logger.info("=== ACCEPT SUGGESTION START ===")
        logger.info("Candidate: \(PrivacyLogger.candidateMetrics(confidence: candidate.confidenceScore, documentCount: candidate.documentCount))")
        logger.info("Fingerprint: \(PrivacyLogger.sanitizeFingerprint(candidate.vendorFingerprint))")
        logger.info("Reminders: \(reminderOffsets.count) offsets")
        logger.info("Duration: \(durationMonths) months")

        do {
            // Step 1: Create template from candidate
            logger.info("STEP 1: Creating template from candidate...")
            let template = try await detectUseCase.acceptCandidate(candidate, reminderOffsets: reminderOffsets)
            // PRIVACY: Log only template ID and sanitized fingerprint
            logger.info("Template created: id=\(template.id), fingerprint=\(PrivacyLogger.sanitizeFingerprint(template.vendorFingerprint))")

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

        // PRIVACY: Log only metrics, not vendor name
        logger.info("Dismissing recurring suggestion: \(PrivacyLogger.candidateMetrics(confidence: candidate.confidenceScore, documentCount: candidate.documentCount))")

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

        // PRIVACY: Log only metrics, not vendor name
        logger.info("Snoozing recurring suggestion: \(PrivacyLogger.candidateMetrics(confidence: candidate.confidenceScore, documentCount: candidate.documentCount))")

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
        // PRIVACY: Log only document ID, not title (contains vendor name)
        logger.info("=== DELETE DOCUMENT - STEP 1 ===")
        logger.info("Document ID: \(document.id)")
        logger.info("Document hasTitle: \(document.title.count > 0)")

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

    /// Sets the filter and triggers a filtered fetch.
    /// - Parameter filter: The new filter to apply
    func setFilter(_ filter: DocumentFilter) {
        guard filter != selectedFilter else { return }

        logger.debug("SET_FILTER: Changing from \(self.selectedFilter.rawValue) to \(filter.rawValue)")
        selectedFilter = filter

        // Trigger filtered fetch
        Task {
            await fetchFilteredDocuments()
        }
    }

    /// Clears the current search text and triggers a refresh.
    func clearSearch() {
        searchText = ""
        // The didSet on searchText will trigger debounced fetch
    }

}

// Note: DocumentFilter enum has been moved to Domain/Models/DocumentFilter.swift
// for use across repository and use case layers.
//
// Resource Cleanup:
// - AnyCancellable (searchDebounceSubscription) automatically cancels on deallocation.
// - Task (detectionTask) is cancelled via cancelPendingDetection() or when the view disappears.
//   Views using this ViewModel should call cancelPendingDetection() in their onDisappear modifier
//   if the ViewModel might outlive the view.
