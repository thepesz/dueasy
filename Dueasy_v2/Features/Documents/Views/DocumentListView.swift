import SwiftUI
import SwiftData

/// Main document list screen (Home).
/// Displays all documents with filtering, search, and swipe-to-delete.
///
/// ARCHITECTURE NOTE: Uses UUID-based navigation to avoid SwiftData object invalidation.
/// The navigation path is managed with UUIDs rather than FinanceDocument objects to
/// ensure stable navigation after documents are added or modified.
///
/// LAYOUT FIX: Accepts a refreshTrigger from MainTabView to properly reset
/// NavigationStack state after sheet dismissals, preventing safe area corruption.
struct DocumentListView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: DocumentListViewModel?
    @State private var showingAddDocument = false
    @State private var navigationPath = NavigationPath()
    @State private var appeared = false

    /// External trigger from MainTabView to refresh after adding documents
    let refreshTrigger: Int

    init(refreshTrigger: Int = 0) {
        self.refreshTrigger = refreshTrigger
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let viewModel = viewModel {
                    documentListContent(viewModel: viewModel)
                } else {
                    LoadingView(L10n.Common.loading.localized)
                        .gradientBackground(style: .list)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAddDocument) {
                AddDocumentView(environment: environment)
                    .environment(environment)
            }
            .onChange(of: showingAddDocument) { oldValue, newValue in
                // Reload documents when sheet is dismissed (false after being true)
                if oldValue && !newValue {
                    Task {
                        await viewModel?.loadDocuments()
                    }
                }
            }
            .onChange(of: refreshTrigger) { oldValue, newValue in
                // External refresh triggered (from MainTabView after adding document)
                // PERFORMANCE: Only clear navigation if we're currently navigated somewhere
                // to avoid unnecessary view updates
                if !navigationPath.isEmpty {
                    navigationPath = NavigationPath()
                }
                Task {
                    await viewModel?.loadDocuments()
                }
            }
            .navigationDestination(for: UUID.self) { documentId in
                let _ = print("NavigationDestination triggered for document ID: \(documentId)")
                DocumentDetailViewWrapper(documentId: documentId)
                    .environment(environment)
            }
        }
        // PERFORMANCE FIX: Removed .id(refreshTrigger) which was causing full NavigationStack
        // recreation and duplicate NavigationDestination triggers. The navigationPath.removeAll()
        // in onChange(of: refreshTrigger) is sufficient to reset navigation state.
        .task {
            setupViewModel()
            await viewModel?.loadDocuments()

            // Trigger appearance animation after data loads
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

    private var appHeader: some View {
        HandwrittenLogo()
    }

    @ViewBuilder
    private func documentListContent(viewModel: DocumentListViewModel) -> some View {
        ZStack {
            // Modern gradient background
            ListGradientBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // App header with handwritten logo
                appHeader
                    .padding(.top, Spacing.md)
                    .padding(.horizontal, Spacing.md)

                // Inline search bar positioned above filters
                InlineSearchBar(
                    text: Binding(
                        get: { viewModel.searchText },
                        set: { viewModel.searchText = $0 }
                    ),
                    placeholder: L10n.Documents.searchPlaceholder.localized
                )
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)

                // Filter bar with glass effect
                filterBar(viewModel: viewModel)
                    .padding(.top, Spacing.sm)

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
        // Fixed-width glass container with horizontally scrolling content inside
        // The glass background stays stationary while filter chips scroll within it
        // PERFORMANCE: Uses CardMaterial for optimized single-layer blur
        ZStack {
            // Glass background (stationary, matches document row styling)
            CardMaterial(cornerRadius: 12, addHighlight: false)
                .overlay { GlassBorder(cornerRadius: 12, lineWidth: 0.5) }

            // Scrollable filter chips inside the glass container
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
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, Spacing.md)
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
                        print("Appending document ID to navigation path: \(document.id)")
                        navigationPath.append(document.id)
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
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
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

// MARK: - Handwritten Logo Component

/// A casual handmade-style logo for DuEasy.
/// Designed to look friendly and approachable, like handwritten text.
///
/// Design rationale:
/// - Uses rounded italic fonts for a casual, friendly handmade feel
/// - Subtle rotation and offset give natural handwritten character
/// - Shadow adds depth without being too formal
/// - Gradient maintains brand identity
/// - Centered with descriptive tagline
///
/// Accessibility:
/// - Respects reduceTransparency: disables blur/shadow layers
/// - Works in both light and dark mode with appropriate colors
struct HandwrittenLogo: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scanPosition: CGFloat = -1.0

    /// Logo gradient colors - sophisticated blue tones
    private var logoGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.15, green: 0.35, blue: 0.65),  // Deep ink blue
                AppColors.primary,                          // Brand blue
                Color(red: 0.25, green: 0.45, blue: 0.75)   // Lighter accent
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Ink shadow color for pen effect
    private var inkShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.5)
            : Color(red: 0.1, green: 0.15, blue: 0.3).opacity(0.3)
    }

    /// Paper highlight for embossed effect
    private var highlightColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.6)
    }

    var body: some View {
        VStack(alignment: .center, spacing: Spacing.xxs) {
            // Main logo with handwritten styling
            ZStack {
                // Layer 1: Soft shadow for depth
                if !reduceTransparency {
                    logoText
                        .foregroundStyle(inkShadowColor)
                        .blur(radius: 1.5)
                        .offset(x: 0.5, y: 1.5)
                }

                // Layer 2: Main text with gradient
                logoText
                    .foregroundStyle(logoGradient)
                    .overlay {
                        // Scanning light effect (green glow)
                        if !reduceMotion {
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.green.opacity(0),
                                                Color.green.opacity(0.6),
                                                Color.green.opacity(0.8),
                                                Color.green.opacity(0.6),
                                                Color.green.opacity(0)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geometry.size.width * 0.3)
                                    .offset(x: geometry.size.width * scanPosition)
                                    .blendMode(.plusLighter)
                            }
                            .mask(logoText)
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .onAppear {
                if !reduceMotion {
                    withAnimation(
                        .linear(duration: 2.5)
                        .repeatForever(autoreverses: true)
                    ) {
                        scanPosition = 1.0
                    }
                }
            }

            // Tagline
            Text(L10n.App.tagline.localized)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1.5)
                .textCase(.uppercase)
        }
    }

    /// The main logo text with casual handmade styling
    private var logoText: some View {
        HStack(alignment: .bottom, spacing: 2) {
            // "Du" with casual friendly style
            Text("Du")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .italic()
                .rotationEffect(.degrees(-3), anchor: .bottom)

            // "Easy" with playful handmade feel
            Text("Easy")
                .font(.system(size: 38, weight: .medium, design: .rounded))
                .italic()
                .rotationEffect(.degrees(2), anchor: .bottom)
                .offset(y: 2)
        }
        .kerning(-0.5)
    }

    /// Decorative flourish line below the logo
    private var flourishLine: some View {
        GeometryReader { geometry in
            Path { path in
                let width = min(geometry.size.width * 0.4, 120)
                let height: CGFloat = 3

                // Start with a small loop (pen landing)
                path.move(to: CGPoint(x: 0, y: height * 0.5))

                // Elegant S-curve flourish
                path.addCurve(
                    to: CGPoint(x: width * 0.3, y: 0),
                    control1: CGPoint(x: width * 0.1, y: height * 0.8),
                    control2: CGPoint(x: width * 0.2, y: height * 0.2)
                )

                path.addCurve(
                    to: CGPoint(x: width * 0.7, y: height),
                    control1: CGPoint(x: width * 0.4, y: -height * 0.3),
                    control2: CGPoint(x: width * 0.6, y: height * 0.8)
                )

                // Taper to a point (pen lifting)
                path.addCurve(
                    to: CGPoint(x: width, y: height * 0.3),
                    control1: CGPoint(x: width * 0.85, y: height * 1.2),
                    control2: CGPoint(x: width * 0.95, y: height * 0.5)
                )
            }
            .stroke(
                logoGradient,
                style: StrokeStyle(
                    lineWidth: 1.5,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .opacity(0.6)
        }
        .frame(height: 6)
    }
}

// MARK: - Inline Search Bar

/// A custom inline search bar with glass morphism styling.
/// Positioned directly above the document list for quick access.
///
/// Design rationale:
/// - Uses ultraThinMaterial for iOS 26 Liquid Glass aesthetic
/// - Matches the filter bar visual language
/// - Provides clear visual feedback during focus
struct InlineSearchBar: View {

    @Binding var text: String
    let placeholder: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isFocused ? AppColors.primary : .secondary)

            // Text field
            TextField(placeholder, text: $text)
                .font(Typography.body)
                .foregroundStyle(.primary)
                .focused($isFocused)
                .submitLabel(.search)

            // Clear button (shown when text is not empty)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs + 2)
        .background {
            // PERFORMANCE: Uses CardMaterial for optimized single-layer blur
            CardMaterial(cornerRadius: 10, addHighlight: false)
        }
        .overlay {
            GlassBorder(
                cornerRadius: 10,
                lineWidth: isFocused ? 1.5 : 0.5,
                accentColor: isFocused ? AppColors.primary : nil
            )
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
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
                // PERFORMANCE: Uses CapsuleMaterial for optimized single-layer blur
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
                    CapsuleMaterial()
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
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Document Detail Wrapper

/// Wrapper view that passes document ID to detail view.
/// This ensures navigation always works even after adding new documents.
struct DocumentDetailViewWrapper: View {

    @Environment(AppEnvironment.self) private var environment
    let documentId: UUID

    var body: some View {
        let _ = print("DocumentDetailViewWrapper created for ID: \(documentId)")
        DocumentDetailView(documentId: documentId)
            .environment(environment)
    }
}

// MARK: - Preview

#Preview {
    DocumentListView()
        .environment(AppEnvironment.preview)
}
