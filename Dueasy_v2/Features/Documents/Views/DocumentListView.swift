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

    /// Guards against stale navigation destinations firing during refresh.
    /// When true, navigationDestination callbacks are blocked to prevent phantom navigation.
    @State private var isRefreshing = false

    /// Candidate being accepted (shows reminder selection sheet)
    @State private var candidateToAccept: RecurringCandidate?

    /// Recurring deletion view model (for documents linked to recurring payments)
    @State private var recurringDeletionViewModel: RecurringDeletionViewModel?

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
            .sheet(item: $candidateToAccept) { candidate in
                AcceptRecurringSheet(
                    candidate: candidate,
                    onAccept: { reminderOffsets, durationMonths in
                        Task {
                            await viewModel?.acceptSuggestion(
                                candidate,
                                reminderOffsets: reminderOffsets,
                                durationMonths: durationMonths
                            )
                        }
                        candidateToAccept = nil
                    },
                    onCancel: {
                        candidateToAccept = nil
                    }
                )
                .environment(environment)
            }
            // Step 1: Initial delete confirmation alert (like iOS Calendar)
            .alert(
                L10n.Documents.deleteInvoiceTitle.localized,
                isPresented: Binding(
                    get: { viewModel?.showDeleteConfirmation ?? false },
                    set: { if !$0 { viewModel?.showDeleteConfirmation = false } }
                ),
                presenting: viewModel?.documentPendingDeletion
            ) { document in
                Button(L10n.Common.delete.localized, role: .destructive) {
                    Task {
                        await viewModel?.confirmDeleteDocument()
                    }
                }
                Button(L10n.Common.cancel.localized, role: .cancel) {
                    viewModel?.cancelDeleteDocument()
                }
            } message: { document in
                Text(document.title)
            }
            // Step 2: Recurring deletion options sheet (only shown if document is linked to recurring)
            .sheet(isPresented: Binding(
                get: { viewModel?.showRecurringDeletionSheet ?? false },
                set: { if !$0 { viewModel?.showRecurringDeletionSheet = false } }
            )) {
                if let vm = viewModel,
                   let document = vm.documentPendingDeletion,
                   let deletionVM = recurringDeletionViewModel {
                    RecurringDocumentDeletionSheet(viewModel: deletionVM) { result in
                        print("🟢 COMPLETION_HANDLER: Received deletion result")
                        print("🟢 COMPLETION_HANDLER: result.success = \(result.success)")
                        print("🟢 COMPLETION_HANDLER: result.documentDeleted = \(result.documentDeleted)")
                        print("🟢 COMPLETION_HANDLER: result.templateDeactivated = \(result.templateDeactivated)")
                        print("🟢 COMPLETION_HANDLER: result.deletedInstanceCount = \(result.deletedInstanceCount)")
                        print("🟢 COMPLETION_HANDLER: result.option = '\(result.option)'")

                        // Always refresh the document list after successful recurring deletion
                        // This handles both cases:
                        // 1. Document was deleted (documentDeleted = true) - removed from list
                        // 2. Future instances were deleted but document kept (templateDeactivated = true) - still in list but unlinked
                        if result.success {
                            print("🟢 COMPLETION_HANDLER: Success=true, calling loadDocuments()")
                            Task {
                                print("🟢 COMPLETION_HANDLER: Awaiting loadDocuments()...")
                                await viewModel?.loadDocuments()
                                print("🟢 COMPLETION_HANDLER: loadDocuments() completed")
                            }
                        } else {
                            print("🟢 COMPLETION_HANDLER: Success=false, skipping loadDocuments()")
                        }

                        print("🟢 COMPLETION_HANDLER: Cleaning up sheet state")
                        viewModel?.showRecurringDeletionSheet = false
                        viewModel?.documentPendingDeletion = nil
                        recurringDeletionViewModel = nil
                        print("🟢 COMPLETION_HANDLER: Cleanup complete")
                    }
                }
            }
            .onChange(of: showingAddDocument) { oldValue, newValue in
                // Reload documents when sheet is dismissed (false after being true)
                if oldValue && !newValue {
                    Task {
                        await viewModel?.loadDocuments()
                    }
                }
            }
            .onChange(of: viewModel?.showRecurringDeletionSheet ?? false) { oldValue, newValue in
                // Set up recurring deletion view model when sheet is about to show
                if newValue && !oldValue, let document = viewModel?.documentPendingDeletion {
                    let deletionVM = environment.makeRecurringDeletionViewModel()
                    recurringDeletionViewModel = deletionVM
                    Task {
                        await deletionVM.setupForDocumentDeletion(document: document, template: nil)
                    }
                }
            }
            .onChange(of: refreshTrigger) { oldValue, newValue in
                // External refresh triggered (from MainTabView after adding document)
                // CRITICAL: Set refresh guard BEFORE clearing path to block stale navigationDestination callbacks
                isRefreshing = true

                // Clear navigation to return to list view
                if !navigationPath.isEmpty {
                    navigationPath = NavigationPath()
                }

                Task {
                    await viewModel?.loadDocuments()
                    // Allow view hierarchy to fully settle before re-enabling navigation
                    try? await Task.sleep(for: .milliseconds(200))
                    isRefreshing = false
                }
            }
            .navigationDestination(for: UUID.self) { documentId in
                // CRITICAL: Block stale navigation during refresh cycle to prevent phantom views
                // that corrupt the layout. When isRefreshing is true, return an empty view.
                if isRefreshing {
                    let _ = print("NavigationDestination BLOCKED (refreshing) for document ID: \(documentId)")
                    Color.clear
                } else {
                    let _ = print("NavigationDestination triggered for document ID: \(documentId)")
                    DocumentDetailViewWrapper(documentId: documentId)
                        .environment(environment)
                }
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

                // Recurring payment suggestions (shown when detected)
                if viewModel.hasSuggestions {
                    recurringSuggestionsSection(viewModel: viewModel)
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.sm)
                }

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

    // MARK: - Recurring Suggestions Section

    @ViewBuilder
    private func recurringSuggestionsSection(viewModel: DocumentListViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Section header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppColors.primary)
                Text(L10n.RecurringSuggestions.sectionTitle.localized)
                    .font(Typography.subheadline.weight(.semibold))
                Spacer()
            }

            // Show first suggestion card (compact inline version)
            if let firstCandidate = viewModel.suggestedCandidates.first {
                InlineSuggestionCard(
                    candidate: firstCandidate,
                    totalCount: viewModel.suggestedCandidates.count,
                    onAccept: {
                        candidateToAccept = firstCandidate
                    },
                    onDismiss: {
                        Task {
                            await viewModel.dismissSuggestion(firstCandidate)
                        }
                    },
                    onSnooze: {
                        Task {
                            await viewModel.snoozeSuggestion(firstCandidate)
                        }
                    }
                )
            }
        }
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
        List {
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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.md, bottom: Spacing.xs, trailing: Spacing.md))
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
            deleteUseCase: environment.makeDeleteDocumentUseCase(),
            detectCandidatesUseCase: environment.makeDetectRecurringCandidatesUseCase(),
            schedulerService: environment.recurringSchedulerService,
            linkExistingDocumentsUseCase: environment.makeLinkExistingDocumentsUseCase(),
            documentRepository: environment.documentRepository
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

// MARK: - Inline Suggestion Card

/// Compact suggestion card shown inline in the document list.
/// Displays recurring payment detection with quick actions.
struct InlineSuggestionCard: View {

    @Environment(\.colorScheme) private var colorScheme

    let candidate: RecurringCandidate
    let totalCount: Int
    let onAccept: () -> Void
    let onDismiss: () -> Void
    let onSnooze: () -> Void

    @State private var isProcessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Main content
            HStack(spacing: Spacing.sm) {
                // Icon
                Image(systemName: candidate.documentCategory.iconName)
                    .font(.title3)
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 36, height: 36)
                    .background(AppColors.primary.opacity(0.1))
                    .clipShape(Circle())

                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.vendorDisplayName)
                        .font(Typography.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(suggestionMessage)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                // Confidence badge
                Text("\(Int(candidate.confidenceScore * 100))%")
                    .font(Typography.caption2.weight(.semibold))
                    .foregroundStyle(confidenceColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(confidenceColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Action buttons
            HStack(spacing: Spacing.xs) {
                // Dismiss button
                Button(action: {
                    isProcessing = true
                    onDismiss()
                }) {
                    Text(L10n.RecurringSuggestions.dismiss.localized)
                        .font(Typography.caption1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isProcessing)

                // Snooze button
                Button(action: {
                    isProcessing = true
                    onSnooze()
                }) {
                    Text(L10n.RecurringSuggestions.snooze.localized)
                        .font(Typography.caption1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isProcessing)

                Spacer()

                // Accept button
                Button(action: {
                    isProcessing = true
                    onAccept()
                }) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text(L10n.RecurringSuggestions.accept.localized)
                            .font(Typography.caption1.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AppColors.primary)
                .disabled(isProcessing)
            }

            // Show count if more suggestions
            if totalCount > 1 {
                Text(L10n.RecurringSuggestions.moreSuggestions.localized(with: totalCount - 1))
                    .font(Typography.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.sm)
        .background {
            CardMaterial(cornerRadius: 12, addHighlight: false)
        }
        .overlay {
            GlassBorder(cornerRadius: 12, lineWidth: 1, accentColor: AppColors.primary.opacity(0.5))
        }
    }

    private var suggestionMessage: String {
        let count = candidate.documentCount
        if let dueDay = candidate.dominantDueDayOfMonth {
            return L10n.RecurringSuggestions.inlineDescription.localized(with: count, dueDay)
        } else {
            return L10n.RecurringSuggestions.inlineDescriptionNoDueDay.localized(with: count)
        }
    }

    private var confidenceColor: Color {
        if candidate.confidenceScore >= 0.9 {
            return AppColors.success
        } else if candidate.confidenceScore >= 0.8 {
            return AppColors.primary
        } else {
            return AppColors.warning
        }
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

// MARK: - Accept Recurring Sheet

/// Sheet for accepting a recurring payment suggestion with reminder customization.
struct AcceptRecurringSheet: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let candidate: RecurringCandidate
    let onAccept: ([Int], Int) -> Void
    let onCancel: () -> Void

    @State private var selectedReminderOffsets: Set<Int>
    @State private var selectedDurationMonths: Int = 12
    @State private var appeared = false

    init(
        candidate: RecurringCandidate,
        onAccept: @escaping ([Int], Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.candidate = candidate
        self.onAccept = onAccept
        self.onCancel = onCancel
        // Initialize with default reminder offsets from settings
        _selectedReminderOffsets = State(initialValue: Set([7, 1, 0]))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Candidate info
                    candidateInfoCard
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3), value: appeared)

                    // Duration settings
                    durationSettings
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.1), value: appeared)

                    // Reminder settings
                    reminderSettings
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.15), value: appeared)

                    // Accept button
                    acceptButton
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.2), value: appeared)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background {
                GradientBackgroundFixed()
            }
            .navigationTitle(L10n.RecurringSuggestions.setupReminders.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel.localized) {
                        onCancel()
                    }
                }
            }
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

    // MARK: - Candidate Info Card

    @ViewBuilder
    private var candidateInfoCard: some View {
        Card.glass {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: candidate.documentCategory.iconName)
                        .font(.title)
                        .foregroundStyle(AppColors.primary)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(candidate.vendorDisplayName)
                            .font(Typography.headline)

                        Text(candidatePattern)
                            .font(Typography.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Confidence badge
                    VStack(spacing: 2) {
                        Text("\(Int(candidate.confidenceScore * 100))%")
                            .font(Typography.caption1.weight(.bold))
                            .foregroundStyle(confidenceColor)

                        Text(L10n.RecurringSuggestions.confidence.localized)
                            .font(Typography.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()
                    .padding(.vertical, Spacing.xxs)

                // Pattern details
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    detailRow(
                        icon: "calendar",
                        label: L10n.RecurringSuggestions.documentsFound.localized,
                        value: "\(candidate.documentCount)"
                    )

                    if let dueDay = candidate.dominantDueDayOfMonth {
                        detailRow(
                            icon: "bell",
                            label: L10n.RecurringSuggestions.typicalDueDate.localized,
                            value: L10n.RecurringSuggestions.dayOfMonth.localized(with: dueDay)
                        )
                    }

                    if let avgAmount = candidate.averageAmount {
                        detailRow(
                            icon: "dollarsign.circle",
                            label: L10n.RecurringSuggestions.averageAmount.localized,
                            value: formatCurrency(avgAmount, currency: candidate.currency)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(Typography.caption1)
                .foregroundStyle(AppColors.primary)
                .frame(width: 20)

            Text(label)
                .font(Typography.caption1)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(Typography.caption1.weight(.semibold))
        }
    }

    // MARK: - Duration Settings

    @ViewBuilder
    private var durationSettings: some View {
        Card.glass {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label(L10n.RecurringSuggestions.durationTitle.localized, systemImage: "calendar.badge.clock")
                    .font(Typography.headline)
                    .foregroundStyle(AppColors.primary)

                Text(L10n.RecurringSuggestions.durationDescription.localized)
                    .font(Typography.caption1)
                    .foregroundStyle(.secondary)

                // Month selection using Stepper with custom display
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.RecurringSuggestions.selectedDuration.localized)
                                .font(Typography.caption1)
                                .foregroundStyle(.secondary)

                            Text(L10n.RecurringSuggestions.monthsCount.localized(with: selectedDurationMonths))
                                .font(Typography.title3.weight(.semibold))
                                .foregroundStyle(AppColors.primary)
                        }

                        Spacer()

                        // Stepper controls
                        HStack(spacing: Spacing.xs) {
                            Button(action: {
                                if selectedDurationMonths > 1 {
                                    selectedDurationMonths -= 1
                                }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(selectedDurationMonths > 1 ? AppColors.primary : Color.gray.opacity(0.3))
                            }
                            .disabled(selectedDurationMonths <= 1)

                            Button(action: {
                                if selectedDurationMonths < 36 {
                                    selectedDurationMonths += 1
                                }
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(selectedDurationMonths < 36 ? AppColors.primary : Color.gray.opacity(0.3))
                            }
                            .disabled(selectedDurationMonths >= 36)
                        }
                    }
                    .padding(Spacing.sm)
                    .background(AppColors.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Quick selection buttons
                    HStack(spacing: Spacing.xs) {
                        ForEach([3, 6, 12, 24], id: \.self) { months in
                            Button(action: {
                                selectedDurationMonths = months
                            }) {
                                Text("\(months)")
                                    .font(Typography.caption1.weight(.medium))
                                    .foregroundStyle(selectedDurationMonths == months ? .white : AppColors.primary)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing.xs)
                                    .background(selectedDurationMonths == months ? AppColors.primary : AppColors.primary.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }

                        Spacer()
                    }

                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "info.circle")
                            .font(Typography.caption2)
                        Text(L10n.RecurringSuggestions.durationHint.localized)
                            .font(Typography.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Reminder Settings

    @ViewBuilder
    private var reminderSettings: some View {
        Card.glass {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label(L10n.Review.remindersTitle.localized, systemImage: "bell.fill")
                    .font(Typography.headline)
                    .foregroundStyle(AppColors.primary)

                Text(L10n.RecurringSuggestions.reminderDescription.localized)
                    .font(Typography.caption1)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: Spacing.xs) {
                    ForEach(SettingsManager.availableReminderOffsets, id: \.self) { offset in
                        ReminderChip(
                            offset: offset,
                            isSelected: selectedReminderOffsets.contains(offset)
                        ) {
                            toggleReminderOffset(offset)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Accept Button

    @ViewBuilder
    private var acceptButton: some View {
        PrimaryButton(
            L10n.RecurringSuggestions.createRecurring.localized,
            icon: "checkmark.circle.fill"
        ) {
            let offsets = Array(selectedReminderOffsets).sorted(by: >)
            onAccept(offsets, selectedDurationMonths)
            dismiss()
        }
    }

    // MARK: - Helpers

    private var candidatePattern: String {
        if let dueDay = candidate.dominantDueDayOfMonth {
            return L10n.RecurringSuggestions.patternWithDueDay.localized(with: candidate.documentCount, dueDay)
        } else {
            return L10n.RecurringSuggestions.patternNoDueDay.localized(with: candidate.documentCount)
        }
    }

    private var confidenceColor: Color {
        if candidate.confidenceScore >= 0.9 {
            return AppColors.success
        } else if candidate.confidenceScore >= 0.8 {
            return AppColors.primary
        } else {
            return AppColors.warning
        }
    }

    private func toggleReminderOffset(_ offset: Int) {
        if selectedReminderOffsets.contains(offset) {
            selectedReminderOffsets.remove(offset)
        } else {
            selectedReminderOffsets.insert(offset)
        }
    }

    private func formatCurrency(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount) \(currency)"
    }
}

// MARK: - Preview

#Preview {
    DocumentListView()
        .environment(AppEnvironment.preview)
}
