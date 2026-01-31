import Foundation

/// Protocol for document synchronization with backend.
/// Iteration 1: No-op implementation (fully local).
/// Iteration 2: Real sync with backend API.
protocol SyncServiceProtocol: Sendable {

    /// Current sync status.
    var syncStatus: SyncStatus { get async }

    /// Whether sync is available (user logged in, network available).
    var isSyncAvailable: Bool { get async }

    /// Syncs all documents with the backend.
    /// - Returns: Sync result with statistics
    /// - Throws: Sync errors
    func syncAll() async throws -> SyncResult

    /// Syncs a single document.
    /// - Parameter documentId: Local document ID
    /// - Returns: Remote document ID if synced
    /// - Throws: Sync errors
    func syncDocument(documentId: String) async throws -> String?

    /// Downloads a document from the backend.
    /// - Parameter remoteId: Remote document ID
    /// - Returns: Downloaded document data
    /// - Throws: Sync errors
    func downloadDocument(remoteId: String) async throws -> SyncedDocumentData?

    /// Gets the last sync timestamp.
    var lastSyncTimestamp: Date? { get }

    /// Marks a document as needing sync.
    /// - Parameter documentId: Local document ID
    func markForSync(documentId: String) async

    /// Gets all documents pending sync.
    /// - Returns: Array of document IDs pending sync
    func getPendingSyncDocumentIds() async -> [String]
}

/// Sync status
enum SyncStatus: Sendable {
    case idle
    case syncing
    case error(String)
    case disabled // Iteration 1 state
}

/// Sync operation result
struct SyncResult: Sendable {
    let uploaded: Int
    let downloaded: Int
    let conflicts: Int
    let errors: [String]
    let timestamp: Date
}

/// Data for a synced document
struct SyncedDocumentData: Sendable {
    let remoteId: String
    let metadata: [String: String]
    let analysisResult: DocumentAnalysisResult?
}

// MARK: - No-Op Implementation for Iteration 1

/// No-op sync service for Iteration 1 (fully local).
final class NoOpSyncService: SyncServiceProtocol, @unchecked Sendable {

    var syncStatus: SyncStatus {
        get async { .disabled }
    }

    var isSyncAvailable: Bool {
        get async { false }
    }

    var lastSyncTimestamp: Date? { nil }

    func syncAll() async throws -> SyncResult {
        SyncResult(uploaded: 0, downloaded: 0, conflicts: 0, errors: [], timestamp: Date())
    }

    func syncDocument(documentId: String) async throws -> String? {
        nil
    }

    func downloadDocument(remoteId: String) async throws -> SyncedDocumentData? {
        nil
    }

    func markForSync(documentId: String) async {
        // No-op
    }

    func getPendingSyncDocumentIds() async -> [String] {
        []
    }
}
