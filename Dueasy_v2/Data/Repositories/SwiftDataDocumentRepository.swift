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
        // Fetch all and filter since Predicate doesn't support optional unwrapping well
        let allDocuments = try await fetchAll()
        return allDocuments.filter { document in
            guard let dueDate = document.dueDate else { return false }
            return dueDate >= startDate && dueDate <= endDate
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    func fetchOverdue() async throws -> [FinanceDocument] {
        let now = Date()
        // Fetch all and filter since Predicate doesn't support optional unwrapping well
        let allDocuments = try await fetchAll()
        return allDocuments.filter { document in
            guard let dueDate = document.dueDate else { return false }
            return dueDate < now &&
                document.status != .paid &&
                document.status != .archived
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    func fetch(byVendorFingerprint vendorFingerprint: String) async throws -> [FinanceDocument] {
        logger.info("=== FETCH BY VENDOR FINGERPRINT ===")
        logger.info("Searching for fingerprint: '\(vendorFingerprint.prefix(32))...'")
        logger.info("Full fingerprint length: \(vendorFingerprint.count)")

        let predicate = #Predicate<FinanceDocument> { document in
            document.vendorFingerprint == vendorFingerprint
        }
        let descriptor = FetchDescriptor<FinanceDocument>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )

        do {
            let results = try modelContext.fetch(descriptor)
            logger.info("Fetch returned \(results.count) documents")

            // DIAGNOSTIC: If no results, check what fingerprints exist
            if results.isEmpty {
                logger.warning("NO MATCHES - checking what fingerprints exist in database...")
                let allDescriptor = FetchDescriptor<FinanceDocument>()
                let allDocs = try modelContext.fetch(allDescriptor)
                logger.warning("Total documents: \(allDocs.count)")
                for doc in allDocs {
                    if let fp = doc.vendorFingerprint {
                        let matches = fp == vendorFingerprint
                        logger.warning("  '\(doc.title)': fp='\(fp.prefix(32))...' MATCHES=\(matches)")
                    } else {
                        logger.warning("  '\(doc.title)': fp=nil")
                    }
                }
            }

            return results
        } catch {
            throw AppError.repositoryFetchFailed(error.localizedDescription)
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
