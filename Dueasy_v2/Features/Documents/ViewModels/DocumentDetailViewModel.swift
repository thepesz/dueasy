import Foundation
import Observation

/// ViewModel for document detail screen.
/// Handles mark as paid and delete operations.
@Observable
@MainActor
final class DocumentDetailViewModel {

    // MARK: - State

    private(set) var isLoading = false
    private(set) var error: AppError?
    private(set) var shouldDismiss = false

    // MARK: - Dependencies

    private let documentId: UUID
    private let markAsPaidUseCase: MarkAsPaidUseCase
    private let deleteUseCase: DeleteDocumentUseCase

    // MARK: - Init

    init(
        documentId: UUID,
        markAsPaidUseCase: MarkAsPaidUseCase,
        deleteUseCase: DeleteDocumentUseCase
    ) {
        self.documentId = documentId
        self.markAsPaidUseCase = markAsPaidUseCase
        self.deleteUseCase = deleteUseCase
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
