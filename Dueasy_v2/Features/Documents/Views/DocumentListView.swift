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
///
/// UI STYLE: Adapts to the current UI style (Midnight Aurora, Paper Minimal, Warm Finance)
/// based on user preference from SettingsManager.uiStyleOtherViews.
struct DocumentListView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    /// Current UI style from settings
    private var currentStyle: UIStyleProposal {
        environment.settingsManager.uiStyle(for: .otherViews)
    }

    /// Design tokens for the current style
    private var tokens: UIStyleTokens {
        UIStyleTokens(style: currentStyle)
    }

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

    /// Initial filter to apply when the view first appears (e.g., from overdue navigation)
    let initialFilter: DocumentFilter?

    init(refreshTrigger: Int = 0, initialFilter: DocumentFilter? = nil) {
        self.refreshTrigger = refreshTrigger
        self.initialFilter = initialFilter
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let viewModel = viewModel {
                    documentListContent(viewModel: viewModel)
                } else {
                    LoadingView(L10n.Common.loading.localized)
                        .styledDocumentListBackground()
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
                   vm.documentPendingDeletion != nil,
                   let deletionVM = recurringDeletionViewModel {
                    RecurringDocumentDeletionSheet(viewModel: deletionVM) { result in
                        #if DEBUG
                        print("COMPLETION_HANDLER: success=\(result.success), docDeleted=\(result.documentDeleted), instancesDeleted=\(result.deletedInstanceCount)")
                        #endif

                        // Always refresh the document list after successful recurring deletion
                        // This handles both cases:
                        // 1. Document was deleted (documentDeleted = true) - removed from list
                        // 2. Future instances were deleted but document kept (templateDeactivated = true) - still in list but unlinked
                        if result.success {
                            Task {
                                await viewModel?.loadDocuments()
                            }
                        }

                        viewModel?.showRecurringDeletionSheet = false
                        viewModel?.documentPendingDeletion = nil
                        recurringDeletionViewModel = nil
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
                // External refresh triggered (from MainTabView after adding document or navigating with filter)
                // CRITICAL: Set refresh guard BEFORE clearing path to block stale navigationDestination callbacks
                isRefreshing = true

                // Clear navigation to return to list view
                if !navigationPath.isEmpty {
                    navigationPath = NavigationPath()
                }

                // Apply initial filter if specified (e.g., from overdue navigation)
                if let initialFilter = initialFilter {
                    viewModel?.setFilter(initialFilter)
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
                    Color.clear
                } else {
                    DocumentDetailViewWrapper(documentId: documentId)
                        .environment(environment)
                }
            }
        }
        // Apply UI style to the environment
        .environment(\.uiStyle, currentStyle)
        // PERFORMANCE FIX: Removed .id(refreshTrigger) which was causing full NavigationStack
        // recreation and duplicate NavigationDestination triggers. The navigationPath.removeAll()
        // in onChange(of: refreshTrigger) is sufficient to reset navigation state.
        .task {
            setupViewModel()

            // Apply initial filter if specified (e.g., from overdue navigation)
            if let initialFilter = initialFilter {
                viewModel?.setFilter(initialFilter)
            }

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
        // CRITICAL FIX: Refresh data when the view becomes visible again.
        // This ensures the document list is always up-to-date when user switches to Documents tab,
        // especially after adding documents in rapid succession.
        .onAppear {
            // Only refresh if ViewModel is already set up (not on first appear, which uses .task)
            if viewModel != nil && appeared {
                Task {
                    await viewModel?.loadDocuments()
                }
            }
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    private func documentListContent(viewModel: DocumentListViewModel) -> some View {
        ZStack {
            // Style-aware background - tap to dismiss keyboard
            StyledDocumentListBackground()
                .ignoresSafeArea()
                .onTapGesture {
                    dismissKeyboard()
                }

            VStack(spacing: 0) {
                // FIXED HEADER SECTION - Does NOT scroll with content
                // This VStack stays pinned at the top
                VStack(spacing: 0) {
                    // Recurring payment suggestions (shown when detected)
                    if viewModel.hasSuggestions {
                        recurringSuggestionsSection(viewModel: viewModel)
                            .padding(.horizontal, Spacing.md)
                            .padding(.top, Spacing.md)
                    }

                    // Styled inline search bar positioned above filters
                    StyledSearchBar(
                        text: Binding(
                            get: { viewModel.searchText },
                            set: { viewModel.searchText = $0 }
                        ),
                        placeholder: L10n.Documents.searchPlaceholder.localized
                    )
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, viewModel.hasSuggestions ? Spacing.sm : Spacing.md)

                    // Styled filter bar - FIXED at top, horizontal scroll only
                    filterBar(viewModel: viewModel)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.xs)
                }

                // SCROLLABLE CONTENT SECTION - Only this part scrolls vertically
                // The .refreshable is applied here so only the content area participates in pull-to-refresh
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
                        .refreshable {
                            await viewModel.loadDocuments()
                        }
                }
            }
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
                    .foregroundStyle(tokens.primaryColor(for: colorScheme))
                Text(L10n.RecurringSuggestions.sectionTitle.localized)
                    .font(Typography.subheadline.weight(.semibold))
                Spacer()
            }

            // Show first suggestion card (styled for current UI style)
            if let firstCandidate = viewModel.suggestedCandidates.first {
                StyledSuggestionCard(
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
        StyledFilterBarContainer {
            ForEach(DocumentFilter.allCases) { filter in
                StyledFilterChip(
                    title: filter.displayName,
                    icon: filter.iconName,
                    count: filterCount(for: filter, viewModel: viewModel),
                    isSelected: viewModel.selectedFilter == filter
                ) {
                    viewModel.setFilter(filter)
                }
            }
        }
    }

    private func filterCount(for filter: DocumentFilter, viewModel: DocumentListViewModel) -> Int? {
        switch filter {
        case .all:
            return nil
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
                StyledDocumentListRow(document: document) {
                    navigationPath.append(document.id)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                .animation(
                    reduceMotion ? .none : tokens.animationSpring.delay(Double(index) * tokens.staggerDelay),
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
        // KEYBOARD DISMISSAL: Dismiss keyboard when scrolling the document list
        .scrollDismissesKeyboard(.interactively)
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

    // MARK: - Keyboard Dismissal

    /// Dismisses the keyboard by resigning first responder
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Handwritten Logo Component

/// A style-aware logo for DuEasy.
/// Adapts styling based on the current UI style:
/// - Midnight Aurora: Clean gradient text without rotation (matches demo)
/// - Other styles: Handwritten style with italic and rotation effects
///
/// Accessibility:
/// - Respects reduceTransparency: disables blur/shadow layers
/// - Respects reduceMotion: disables animated scan effect
/// - Works in both light and dark mode with appropriate colors
struct HandwrittenLogo: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.uiStyle) private var style

    @State private var scanPosition: CGFloat = -1.0


    /// Logo gradient colors - sophisticated blue tones (for non-Aurora styles)
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

    var body: some View {
        VStack(alignment: .center, spacing: Spacing.xxs) {
            if style == .midnightAurora {
                // Midnight Aurora style: clean gradient logo without rotation (matches demo)
                midnightAuroraLogo
            } else {
                // Other styles: handwritten style with effects
                handwrittenLogo
            }

            // Tagline - adapts font design to current style
            Text(style == .midnightAurora ? L10n.Home.paymentTracker.localized : L10n.App.tagline.localized)
                .font(.system(size: 11, weight: .medium, design: style == .midnightAurora ? .default : .rounded))
                .foregroundStyle(style == .midnightAurora ? Color.white.opacity(0.75) : .secondary)
                .tracking(style == .midnightAurora ? 3 : 1.5)
                .textCase(.uppercase)
        }
    }

    // MARK: - Midnight Aurora Logo (matches demo)

    private var midnightAuroraLogo: some View {
        HStack(alignment: .bottom, spacing: 2) {
            Text("Du")
                .font(.system(size: 38, weight: .medium, design: .default))
                .foregroundStyle(AuroraGradients.logoDu)

            Text("Easy")
                .font(.system(size: 38, weight: .light, design: .default))
                .foregroundStyle(AuroraGradients.logoEasy)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Handwritten Logo (for other styles)

    private var handwrittenLogo: some View {
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

// MARK: - Document Detail Wrapper

/// Wrapper view that passes document ID to detail view.
/// This ensures navigation always works even after adding new documents.
struct DocumentDetailViewWrapper: View {

    @Environment(AppEnvironment.self) private var environment
    let documentId: UUID

    var body: some View {
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
