import Foundation
import Observation

/// ViewModel for document detail screen.
/// Handles mark as paid and delete operations.
@Observable
@MainActor
final class DocumentDetailViewModel {

    // MARK: - State

    private(set) var document: FinanceDocument?
    private(set) var isLoading = false
    private(set) var error: AppError?
    private(set) var shouldDismiss = false

    /// Whether this document is linked to a recurring payment
    var isLinkedToRecurring: Bool {
        document?.recurringInstanceId != nil
    }

    /// The recurring template ID if linked
    var recurringTemplateId: UUID? {
        document?.recurringTemplateId
    }

    /// The recurring instance ID if linked
    var recurringInstanceId: UUID? {
        document?.recurringInstanceId
    }

    // MARK: - Dependencies

    private let documentId: UUID
    private let repository: DocumentRepositoryProtocol
    private let markAsPaidUseCase: MarkAsPaidUseCase
    private let deleteUseCase: DeleteDocumentUseCase

    // MARK: - Init

    init(
        documentId: UUID,
        repository: DocumentRepositoryProtocol,
        markAsPaidUseCase: MarkAsPaidUseCase,
        deleteUseCase: DeleteDocumentUseCase
    ) {
        self.documentId = documentId
        self.repository = repository
        self.markAsPaidUseCase = markAsPaidUseCase
        self.deleteUseCase = deleteUseCase
    }

    // MARK: - Loading

    /// Fetches the document from the repository.
    /// This ensures we always have a fresh reference, avoiding stale SwiftData objects.
    func loadDocument() async {
        print("📋 DocumentDetailViewModel.loadDocument() called for ID: \(documentId)")
        isLoading = true
        error = nil

        do {
            document = try await repository.fetch(documentId: documentId)
            print("📋 Document fetched successfully: \(document != nil)")
            if let doc = document {
                print("📋 Document details - Title: \(doc.title), NIP: \(doc.vendorNIP ?? "nil")")
            }
            isLoading = false
        } catch let appError as AppError {
            print("📋 Error loading document: \(appError)")
            error = appError
            isLoading = false
        } catch {
            print("📋 Unknown error loading document: \(error)")
            self.error = .repositoryFetchFailed(error.localizedDescription)
            isLoading = false
        }
    }

    // MARK: - Actions

    /// Marks the document as paid.
    func markAsPaid() async {
        isLoading = true
        error = nil

        do {
            try await markAsPaidUseCase.execute(documentId: documentId)
            isLoading = false
        } catch let appError as AppError {
            error = appError
            isLoading = false
        } catch {
            self.error = .unknown(error.localizedDescription)
            isLoading = false
        }
    }

    /// Deletes the document and all associated data.
    func deleteDocument() async {
        isLoading = true
        error = nil

        do {
            try await deleteUseCase.execute(documentId: documentId)
            isLoading = false
            shouldDismiss = true
        } catch let appError as AppError {
            error = appError
            isLoading = false
        } catch {
            self.error = .unknown(error.localizedDescription)
            isLoading = false
        }
    }

    /// Clears the current error.
    func clearError() {
        error = nil
    }
}
