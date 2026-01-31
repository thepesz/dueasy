import SwiftUI
import SwiftData

/// Main document list screen (Home).
/// Displays all documents with filtering, search, and swipe-to-delete.
struct DocumentListView: View {

    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: DocumentListViewModel?
    @State private var showingAddDocument = false
    @State private var selectedDocument: FinanceDocument?
    @State private var documentToDelete: FinanceDocument?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = viewModel {
                    documentListContent(viewModel: viewModel)
                } else {
                    LoadingView(L10n.Common.loading.localized)
                }
            }
            .navigationTitle(L10n.Documents.title.localized)
            .sheet(isPresented: $showingAddDocument) {
                AddDocumentView(environment: environment)
                    .environment(environment)
            }
            .navigationDestination(item: $selectedDocument) { document in
                DocumentDetailView(document: document)
                    .environment(environment)
            }
            .confirmationDialog(
                L10n.Documents.deleteConfirmTitle.localized,
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(L10n.Common.delete.localized, role: .destructive) {
                    if let document = documentToDelete {
                        Task {
                            await viewModel?.deleteDocument(document)
                        }
                    }
                }
                Button(L10n.Common.cancel.localized, role: .cancel) {
                    documentToDelete = nil
                }
            } message: {
                Text(L10n.Documents.deleteConfirmMessage.localized)
            }
        }
        .task {
            setupViewModel()
            await viewModel?.loadDocuments()
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    private func documentListContent(viewModel: DocumentListViewModel) -> some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar(viewModel: viewModel)

            // Content
            if viewModel.isLoading && !viewModel.hasDocuments {
                LoadingView(L10n.Documents.loadingDocuments.localized)
            } else if !viewModel.hasDocuments {
                EmptyStateView.noDocuments {
                    showingAddDocument = true
                }
            } else if !viewModel.hasFilteredDocuments {
                emptyFilterState(viewModel: viewModel)
            } else {
                documentList(viewModel: viewModel)
            }
        }
        .searchable(
            text: Binding(
                get: { viewModel.searchText },
                set: { viewModel.searchText = $0 }
            ),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: L10n.Documents.searchPlaceholder.localized
        )
        .refreshable {
            await viewModel.loadDocuments()
        }
        .overlay(alignment: .top) {
            if let error = viewModel.error {
                ErrorBanner(
                    error: error,
                    onDismiss: { viewModel.clearError() },
                    onRetry: {
                        Task {
                            await viewModel.loadDocuments()
                        }
                    }
                )
                .padding()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: viewModel.error != nil)
    }

    @ViewBuilder
    private func filterBar(viewModel: DocumentListViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(DocumentFilter.allCases) { filter in
                    FilterChip(
                        title: filter.displayName,
                        icon: filter.iconName,
                        count: filterCount(for: filter, viewModel: viewModel),
                        isSelected: viewModel.selectedFilter == filter
                    ) {
                        viewModel.setFilter(filter)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xxs)
        }
        .background(AppColors.background)
    }

    private func filterCount(for filter: DocumentFilter, viewModel: DocumentListViewModel) -> Int? {
        switch filter {
        case .all:
            return nil
        case .pending:
            return viewModel.statusCounts[.draft]
        case .scheduled:
            return viewModel.statusCounts[.scheduled]
        case .paid:
            return viewModel.statusCounts[.paid]
        case .overdue:
            return viewModel.overdueCount > 0 ? viewModel.overdueCount : nil
        }
    }

    @ViewBuilder
    private func documentList(viewModel: DocumentListViewModel) -> some View {
        List {
            ForEach(viewModel.filteredDocuments) { document in
                DocumentRow(document: document) {
                    selectedDocument = document
                }
                .listRowInsets(EdgeInsets(
                    top: Spacing.xs,
                    leading: Spacing.md,
                    bottom: Spacing.xs,
                    trailing: Spacing.md
                ))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        documentToDelete = document
                        showDeleteConfirmation = true
                    } label: {
                        Label(L10n.Common.delete.localized, systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func emptyFilterState(viewModel: DocumentListViewModel) -> some View {
        if !viewModel.searchText.isEmpty {
            EmptyStateView.noSearchResults(query: viewModel.searchText)
        } else {
            EmptyStateView.noResults(for: viewModel.selectedFilter.displayName)
        }
    }

    // MARK: - Setup

    private func setupViewModel() {
        guard viewModel == nil else { return }
        viewModel = DocumentListViewModel(
            fetchDocumentsUseCase: environment.makeFetchDocumentsUseCase(),
            countDocumentsUseCase: environment.makeCountDocumentsByStatusUseCase(),
            deleteUseCase: environment.makeDeleteDocumentUseCase()
        )
    }
}

// MARK: - Filter Chip

struct FilterChip: View {

    let title: String
    let icon: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: icon)
                    .font(.caption2)

                Text(title)
                    .font(Typography.caption2)

                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(Typography.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.white.opacity(0.3) : AppColors.primary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(isSelected ? AppColors.primary : AppColors.secondaryBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    DocumentListView()
        .environment(AppEnvironment.preview)
}
