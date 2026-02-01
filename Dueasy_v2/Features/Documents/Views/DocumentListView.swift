import SwiftUI
import SwiftData

/// Main document list screen (Home).
/// Displays all documents with filtering, search, and swipe-to-delete.
struct DocumentListView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: DocumentListViewModel?
    @State private var showingAddDocument = false
    @State private var selectedDocument: FinanceDocument?
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = viewModel {
                    documentListContent(viewModel: viewModel)
                } else {
                    LoadingView(L10n.Common.loading.localized)
                        .gradientBackground(style: .list)
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
        }
        .task {
            setupViewModel()
            await viewModel?.loadDocuments()
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.4)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    private func documentListContent(viewModel: DocumentListViewModel) -> some View {
        ZStack {
            // Modern gradient background
            ListGradientBackground()

            VStack(spacing: 0) {
                // Filter bar with glass effect
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
            .padding(.vertical, Spacing.sm)
        }
        .background(.ultraThinMaterial)
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
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(Array(viewModel.filteredDocuments.enumerated()), id: \.element.id) { index, document in
                    DocumentRow(document: document) {
                        selectedDocument = document
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.05),
                        value: appeared
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteDocument(document)
                            }
                        } label: {
                            Label(L10n.Common.delete.localized, systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteDocument(document)
                            }
                        } label: {
                            Label(L10n.Common.delete.localized, systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xl)
        }
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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let icon: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: icon)
                    .font(.caption2)
                    .symbolRenderingMode(.hierarchical)

                Text(title)
                    .font(Typography.caption2.weight(isSelected ? .semibold : .medium))

                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(Typography.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.25) : AppColors.primary.opacity(0.15))
                        )
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.primary,
                                    AppColors.primary.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: AppColors.primary.opacity(0.3), radius: 4, y: 2)
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .light ? 0.6 : 0.2),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        }
                }
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !reduceMotion {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    if !reduceMotion {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isPressed = false
                        }
                    }
                }
        )
    }
}

// MARK: - Preview

#Preview {
    DocumentListView()
        .environment(AppEnvironment.preview)
}
