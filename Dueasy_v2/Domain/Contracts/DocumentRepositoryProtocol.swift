import Foundation

/// Protocol for document persistence operations.
/// Single source of truth: SwiftData store.
protocol DocumentRepositoryProtocol: Sendable {

    // MARK: - CRUD Operations

    /// Creates a new document.
    /// - Parameter document: Document to create
    /// - Throws: `AppError.repositorySaveFailed`
    func create(_ document: FinanceDocument) async throws

    /// Updates an existing document.
    /// - Parameter document: Document with updated values
    /// - Throws: `AppError.repositorySaveFailed`
    func update(_ document: FinanceDocument) async throws

    /// Deletes a document.
    /// - Parameter documentId: ID of document to delete
    /// - Throws: `AppError.repositoryDeleteFailed`
    func delete(documentId: UUID) async throws

    /// Fetches a document by ID.
    /// - Parameter documentId: Document ID
    /// - Returns: Document if found, nil otherwise
    /// - Throws: `AppError.repositoryFetchFailed`
    func fetch(documentId: UUID) async throws -> FinanceDocument?

    // MARK: - Query Operations

    /// Fetches all documents.
    /// - Returns: Array of all documents, sorted by creation date (newest first)
    /// - Throws: `AppError.repositoryFetchFailed`
    func fetchAll() async throws -> [FinanceDocument]

    /// Fetches documents by status.
    /// - Parameter status: Status to filter by
    /// - Returns: Array of documents with the given status
    /// - Throws: `AppError.repositoryFetchFailed`
    func fetch(byStatus status: DocumentStatus) async throws -> [FinanceDocument]

    /// Fetches documents by type.
    /// - Parameter type: Document type to filter by
    /// - Returns: Array of documents with the given type
    /// - Throws: `AppError.repositoryFetchFailed`
    func fetch(byType type: DocumentType) async throws -> [FinanceDocument]

    /// Searches documents by vendor name or title.
    /// - Parameter query: Search query string
    /// - Returns: Array of matching documents
    /// - Throws: `AppError.repositoryFetchFailed`
    func search(query: String) async throws -> [FinanceDocument]

    /// Fetches documents with due dates in a date range.
    /// - Parameters:
    ///   - startDate: Start of date range
    ///   - endDate: End of date range
    /// - Returns: Array of documents with due dates in range
    /// - Throws: `AppError.repositoryFetchFailed`
    func fetch(dueDateBetween startDate: Date, and endDate: Date) async throws -> [FinanceDocument]

    /// Fetches documents that are overdue (due date in past, not paid).
    /// - Returns: Array of overdue documents
    /// - Throws: `AppError.repositoryFetchFailed`
    func fetchOverdue() async throws -> [FinanceDocument]

    /// Fetches documents with combined filter and optional search query.
    /// This method enables database-level filtering for improved performance with large datasets.
    /// - Parameters:
    ///   - filter: Optional document filter (all, pending, scheduled, paid, overdue)
    ///   - searchQuery: Optional search string to match against title, documentNumber, and notes
    /// - Returns: Array of filtered documents, sorted by creation date (newest first)
    /// - Throws: `AppError.repositoryFetchFailed`
    func fetch(filter: DocumentFilter?, searchQuery: String?) async throws -> [FinanceDocument]

    /// Fetches documents by vendor fingerprint (for recurring payment linking).
    /// - Parameter vendorFingerprint: The vendor fingerprint to match
    /// - Returns: Array of documents with matching vendor fingerprint
    /// - Throws: `AppError.repositoryFetchFailed`
    func fetch(byVendorFingerprint vendorFingerprint: String) async throws -> [FinanceDocument]

    // MARK: - Batch Operations

    /// Saves any pending changes.
    /// - Throws: `AppError.repositorySaveFailed`
    func save() async throws

    /// Counts documents by status.
    /// - Returns: Dictionary of status to count
    /// - Throws: `AppError.repositoryFetchFailed`
    func countByStatus() async throws -> [DocumentStatus: Int]

    // MARK: - Cache Management

    /// Forces a re-fetch of a document from the persistent store.
    /// Use this when you need the latest database values after batch operations.
    /// SwiftData caches objects in memory, so this ensures you get fresh data.
    /// - Parameter documentId: ID of the document to refresh
    /// - Returns: Fresh document from the database, or nil if not found
    func fetchFresh(documentId: UUID) async throws -> FinanceDocument?
}
