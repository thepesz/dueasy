import Foundation
import Observation
import SwiftUI

/// ViewModel for the document list screen.
/// Manages document fetching, filtering, and search.
@MainActor
@Observable
final class DocumentListViewModel {

    // MARK: - State

    var documents: [FinanceDocument] = []
    var selectedFilter: DocumentFilter = .all
    var searchText: String = ""
    var isLoading: Bool = false
    var error: AppError?
    var statusCounts: [DocumentStatus: Int] = [:]

    // MARK: - Dependencies

    private let fetchDocumentsUseCase: FetchDocumentsUseCase
    private let countDocumentsUseCase: CountDocumentsByStatusUseCase
    private let deleteUseCase: DeleteDocumentUseCase

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

    // MARK: - Initialization

    init(
        fetchDocumentsUseCase: FetchDocumentsUseCase,
        countDocumentsUseCase: CountDocumentsByStatusUseCase,
        deleteUseCase: DeleteDocumentUseCase
    ) {
        self.fetchDocumentsUseCase = fetchDocumentsUseCase
        self.countDocumentsUseCase = countDocumentsUseCase
        self.deleteUseCase = deleteUseCase
    }

    // MARK: - Actions

    func loadDocuments() async {
        isLoading = true
        error = nil

        do {
            // Proper MVVM flow: ViewModel → UseCase → Repository
            documents = try await fetchDocumentsUseCase.execute()
            statusCounts = try await countDocumentsUseCase.executeAll()
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .repositoryFetchFailed(error.localizedDescription)
        }

        isLoading = false
    }

    func deleteDocument(_ document: FinanceDocument) async {
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
