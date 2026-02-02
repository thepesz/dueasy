import Foundation
import SwiftData
import os.log

/// SwiftData implementation of DocumentRepositoryProtocol.
/// Single source of truth for document persistence.
@MainActor
final class SwiftDataDocumentRepository: DocumentRepositoryProtocol, @unchecked Sendable {

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.dueasy.app", category: "Repository")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - CRUD Operations

    func create(_ document: FinanceDocument) async throws {
        modelContext.insert(document)
        try await save()
    }

    func update(_ document: FinanceDocument) async throws {
        document.markUpdated()
        try await save()
    }

    func delete(documentId: UUID) async throws {
        guard let document = try await fetch(documentId: documentId) else {
            throw AppError.documentNotFound(documentId.uuidString)
        }

        // CRITICAL: Fault in ALL properties before deletion to prevent
        // "detached from context" crash when SwiftUI accesses stale references
        // SwiftData lazy-loads properties, so we must access them before delete
        faultInAllProperties(document)

        modelContext.delete(document)
        try await save()

        logger.debug("Document \(documentId.uuidString) deleted from SwiftData")
    }

    func fetch(documentId: UUID) async throws -> FinanceDocument? {
        let predicate = #Predicate<FinanceDocument> { document in
            document.id == documentId
        }
        let descriptor = FetchDescriptor<FinanceDocument>(predicate: predicate)

        do {
            let results = try modelContext.fetch(descriptor)
            return results.first
        } catch {
            throw AppError.repositoryFetchFailed(error.localizedDescription)
        }
    }

    // MARK: - Query Operations

    func fetchAll() async throws -> [FinanceDocument] {
        let descriptor = FetchDescriptor<FinanceDocument>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw AppError.repositoryFetchFailed(error.localizedDescription)
        }
    }

    func fetch(byStatus status: DocumentStatus) async throws -> [FinanceDocument] {
        let statusRaw = status.rawValue
        let predicate = #Predicate<FinanceDocument> { document in
            document.statusRaw == statusRaw
        }
        let descriptor = FetchDescriptor<FinanceDocument>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw AppError.repositoryFetchFailed(error.localizedDescription)
        }
    }

    func fetch(byType type: DocumentType) async throws -> [FinanceDocument] {
        let typeRaw = type.rawValue
        let predicate = #Predicate<FinanceDocument> { document in
            document.typeRaw == typeRaw
        }
        let descriptor = FetchDescriptor<FinanceDocument>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw AppError.repositoryFetchFailed(error.localizedDescription)
        }
    }

    func search(query: String) async throws -> [FinanceDocument] {
        guard !query.isEmpty else {
            return try await fetchAll()
        }

        let lowercaseQuery = query.lowercased()
        let predicate = #Predicate<FinanceDocument> { document in
            document.title.localizedStandardContains(lowercaseQuery) ||
            (document.documentNumber?.localizedStandardContains(lowercaseQuery) ?? false) ||
            (document.notes?.localizedStandardContains(lowercaseQuery) ?? false)
        }
        let descriptor = FetchDescriptor<FinanceDocument>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw AppError.repositoryFetchFailed(error.localizedDescription)
        }
    }

    func fetch(dueDateBetween startDate: Date, and endDate: Date) async throws -> [FinanceDocument] {
        // Try database-level filtering first for better performance
        // SwiftData predicates can handle optional date comparisons when structured correctly
        do {
            let predicate = #Predicate<FinanceDocument> { document in
                document.dueDate != nil &&
                document.dueDate! >= startDate &&
                document.dueDate! <= endDate
            }

            let descriptor = FetchDescriptor<FinanceDocument>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.dueDate, order: .forward)]
            )

            return try modelContext.fetch(descriptor)
        } catch {
            // Fallback to in-memory filtering if predicate fails
            logger.warning("Date range predicate failed, falling back to in-memory filter: \(error.localizedDescription)")
            let allDocuments = try await fetchAll()
            return allDocuments.filter { document in
                guard let dueDate = document.dueDate else { return false }
                return dueDate >= startDate && dueDate <= endDate
            }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        }
    }

    func fetchOverdue() async throws -> [FinanceDocument] {
        let now = Date()
        let paidStatus = DocumentStatus.paid.rawValue
        let archivedStatus = DocumentStatus.archived.rawValue

        // Try database-level filtering first for better performance
        do {
            let predicate = #Predicate<FinanceDocument> { document in
                document.dueDate != nil &&
                document.dueDate! < now &&
                document.statusRaw != paidStatus &&
                document.statusRaw != archivedStatus
            }

            let descriptor = FetchDescriptor<FinanceDocument>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.dueDate, order: .forward)]
            )

            return try modelContext.fetch(descriptor)
        } catch {
            // Fallback to in-memory filtering if predicate fails
            logger.warning("Overdue predicate failed, falling back to in-memory filter: \(error.localizedDescription)")
            let allDocuments = try await fetchAll()
            return allDocuments.filter { document in
                guard let dueDate = document.dueDate else { return false }
                return dueDate < now &&
                    document.status != .paid &&
                    document.status != .archived
            }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        }
    }

    func fetch(byVendorFingerprint vendorFingerprint: String) async throws -> [FinanceDocument] {
        logger.debug("Fetching documents by vendor fingerprint: \(vendorFingerprint.prefix(16))...")

        let predicate = #Predicate<FinanceDocument> { document in
            document.vendorFingerprint == vendorFingerprint
        }
        let descriptor = FetchDescriptor<FinanceDocument>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )

        do {
            let results = try modelContext.fetch(descriptor)
            logger.debug("Vendor fingerprint fetch returned \(results.count) documents")

            #if DEBUG
            // DEBUG-only: Diagnostic logging for fingerprint matching issues
            if results.isEmpty {
                logger.debug("No matches for fingerprint - checking database...")
                let allDescriptor = FetchDescriptor<FinanceDocument>()
                let allDocs = try modelContext.fetch(allDescriptor)
                logger.debug("Total documents: \(allDocs.count)")
                for doc in allDocs {
                    if let fp = doc.vendorFingerprint {
                        let matches = fp == vendorFingerprint
                        logger.debug("  Doc id=\(doc.id): fpPrefix=\(fp.prefix(8))..., matches=\(matches)")
                    }
                }
            }
            #endif

            return results
        } catch {
            throw AppError.repositoryFetchFailed(error.localizedDescription)
        }
    }

    func fetch(filter: DocumentFilter?, searchQuery: String?) async throws -> [FinanceDocument] {
        // Build the predicate based on filter and search query
        let predicate = buildFilterPredicate(filter: filter, searchQuery: searchQuery)

        let descriptor = FetchDescriptor<FinanceDocument>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        do {
            var results = try modelContext.fetch(descriptor)

            // Handle overdue filter post-fetch since it requires computed logic
            // (dueDate < now AND status != paid AND status != archived)
            // SwiftData predicates don't support complex date comparisons with optionals well
            if filter == .overdue {
                let now = Date()
                results = results.filter { document in
                    guard let dueDate = document.dueDate else { return false }
                    return dueDate < now &&
                        document.status != .paid &&
                        document.status != .archived
                }
            }

            return results
        } catch {
            throw AppError.repositoryFetchFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Filter Helpers

    /// Builds a SwiftData predicate for the given filter and search query.
    /// Optimizes database-level filtering for improved performance.
    private func buildFilterPredicate(filter: DocumentFilter?, searchQuery: String?) -> Predicate<FinanceDocument>? {
        let hasSearch = searchQuery != nil && !searchQuery!.isEmpty
        let lowercaseQuery = searchQuery?.lowercased() ?? ""

        // Map filter to status raw value for predicate
        let statusRaw: String? = {
            switch filter {
            case .pending:
                return DocumentStatus.draft.rawValue
            case .scheduled:
                return DocumentStatus.scheduled.rawValue
            case .paid:
                return DocumentStatus.paid.rawValue
            case .all, .overdue, .none:
                // .all = no status filter
                // .overdue = handled post-fetch (computed)
                // .none = no filter
                return nil
            }
        }()

        // Build predicate based on combination of filter and search
        switch (statusRaw, hasSearch) {
        case (let status?, true):
            // Both status filter and search query
            return #Predicate<FinanceDocument> { document in
                document.statusRaw == status && (
                    document.title.localizedStandardContains(lowercaseQuery) ||
                    (document.documentNumber?.localizedStandardContains(lowercaseQuery) ?? false) ||
                    (document.notes?.localizedStandardContains(lowercaseQuery) ?? false)
                )
            }

        case (let status?, false):
            // Status filter only
            return #Predicate<FinanceDocument> { document in
                document.statusRaw == status
            }

        case (nil, true):
            // Search query only (no status filter)
            return #Predicate<FinanceDocument> { document in
                document.title.localizedStandardContains(lowercaseQuery) ||
                (document.documentNumber?.localizedStandardContains(lowercaseQuery) ?? false) ||
                (document.notes?.localizedStandardContains(lowercaseQuery) ?? false)
            }

        case (nil, false):
            // No filter, no search - return all
            return nil
        }
    }

    // MARK: - Batch Operations

    func save() async throws {
        do {
            try modelContext.save()
        } catch {
            throw AppError.repositorySaveFailed(error.localizedDescription)
        }
    }

    func countByStatus() async throws -> [DocumentStatus: Int] {
        var counts: [DocumentStatus: Int] = [:]

        for status in DocumentStatus.allCases {
            let documents = try await fetch(byStatus: status)
            counts[status] = documents.count
        }

        return counts
    }

    // MARK: - Cache Management

    /// Forces a re-fetch of a document from the persistent store.
    /// Use this when you need the latest database values after batch operations.
    /// SwiftData caches objects in memory, so this ensures you get fresh data.
    ///
    /// Implementation note: SwiftData doesn't have Core Data's refresh() method.
    /// The workaround is to fetch by ID again, which retrieves the current database state.
    /// - Parameter documentId: ID of the document to refresh
    /// - Returns: Fresh document from the database, or nil if not found
    func fetchFresh(documentId: UUID) async throws -> FinanceDocument? {
        logger.debug("FETCH_FRESH: Re-fetching document \(documentId) from database")

        let predicate = #Predicate<FinanceDocument> { document in
            document.id == documentId
        }
        let descriptor = FetchDescriptor<FinanceDocument>(predicate: predicate)

        do {
            let results = try modelContext.fetch(descriptor)
            if let fresh = results.first {
                // Force access to the properties we care about to ensure they're loaded
                let instanceId = fresh.recurringInstanceId
                let templateId = fresh.recurringTemplateId
                logger.debug("FETCH_FRESH: Got document \(fresh.id) - instanceId=\(instanceId?.uuidString ?? "nil"), templateId=\(templateId?.uuidString ?? "nil")")
                return fresh
            }
            logger.warning("FETCH_FRESH: Document \(documentId) not found in database")
            return nil
        } catch {
            throw AppError.repositoryFetchFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    /// Forces SwiftData to load all properties of a document.
    /// This prevents "detached from context" crashes when the document
    /// is deleted but SwiftUI still holds a reference to it.
    ///
    /// SwiftData uses lazy loading (faulting) for properties. If a property
    /// hasn't been accessed before the object is deleted, accessing it after
    /// deletion causes a fatal error.
    private func faultInAllProperties(_ document: FinanceDocument) {
        // Access all properties to ensure they're loaded into memory
        // This is a workaround for SwiftData's lazy loading behavior

        // Basic properties
        _ = document.id
        _ = document.typeRaw
        _ = document.title
        _ = document.amountValue
        _ = document.currency
        _ = document.dueDate
        _ = document.createdAt
        _ = document.updatedAt
        _ = document.statusRaw
        _ = document.notes
        _ = document.sourceFileURL
        _ = document.documentNumber

        // Vendor details
        _ = document.vendorAddress
        _ = document.vendorNIP
        _ = document.bankAccountNumber

        // Calendar & Notifications
        _ = document.calendarEventId
        _ = document.reminderOffsetsDays  // Array - important to fault
        _ = document.notificationsEnabled

        // Iteration 2 fields
        _ = document.remoteDocumentId
        _ = document.remoteFileId
        _ = document.analysisVersion
        _ = document.analysisProvider

        // Computed properties (these access the raw properties above)
        _ = document.type
        _ = document.status
        _ = document.amount
        _ = document.isOverdue
        _ = document.daysUntilDue
    }
}
