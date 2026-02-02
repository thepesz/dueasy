import SwiftUI

/// Calendar view showing documents and recurring instances by due date.
/// Uses a month grid with day badges indicating document counts and urgency.
struct CalendarView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel: CalendarViewModel?

    // Recurring instance deletion state
    @State private var showingRecurringDeletionSheet = false
    @State private var recurringDeletionViewModel: RecurringDeletionViewModel?
    @State private var instanceToDelete: RecurringInstance?

    /// Localized weekday names - computed to respect language changes
    private var weekdays: [String] {
        [
            L10n.Weekdays.monday.localized,
            L10n.Weekdays.tuesday.localized,
            L10n.Weekdays.wednesday.localized,
            L10n.Weekdays.thursday.localized,
            L10n.Weekdays.friday.localized,
            L10n.Weekdays.saturday.localized,
            L10n.Weekdays.sunday.localized
        ]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = viewModel {
                    calendarContent(viewModel: viewModel)
                } else {
                    LoadingView(L10n.CalendarView.loading.localized)
                        .gradientBackground(style: .list)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            setupViewModel()
            await viewModel?.loadDocuments()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func calendarContent(viewModel: CalendarViewModel) -> some View {
        ZStack {
            GradientBackground()

            VStack(spacing: 0) {
                // Month navigation header with glass effect
                monthHeader(viewModel: viewModel)

                // Filter toggle for recurring only
                filterToggle(viewModel: viewModel)

                // Weekday labels
                weekdayLabels

                // Calendar grid
                calendarGrid(viewModel: viewModel)
                    .padding(.bottom, Spacing.md)

                // Selected day documents and recurring instances in glass card
                selectedDaySection(viewModel: viewModel)
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
            }
        }
    }

    // MARK: - Month Header

    @ViewBuilder
    private func monthHeader(viewModel: CalendarViewModel) -> some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.goToPreviousMonth()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.currentMonthName)
                    .font(Typography.title3)

                if !viewModel.isCurrentMonth {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            viewModel.goToToday()
                        }
                    } label: {
                        Text(L10n.CalendarView.today.localized)
                            .font(Typography.caption1.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(
                                Capsule()
                                    .fill(AppColors.primary)
                            )
                    }
                }
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.goToNextMonth()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Filter Toggle

    @ViewBuilder
    private func filterToggle(viewModel: CalendarViewModel) -> some View {
        HStack {
            Spacer()
            Toggle(isOn: Binding(
                get: { viewModel.showRecurringOnly },
                set: { viewModel.showRecurringOnly = $0 }
            )) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "repeat")
                        .font(.caption)
                    Text(L10n.CalendarView.showRecurringOnly.localized)
                        .font(Typography.caption1)
                }
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .tint(viewModel.showRecurringOnly ? AppColors.primary : .secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }

    // MARK: - Weekday Labels

    private var weekdayLabels: some View {
        HStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(Typography.caption1.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }

    // MARK: - Calendar Grid

    @ViewBuilder
    private func calendarGrid(viewModel: CalendarViewModel) -> some View {
        let days = viewModel.daysInMonth
        let firstWeekday = viewModel.firstWeekdayOfMonth
        let calendar = Calendar.current

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            // Empty cells for days before the first of the month
            ForEach(0..<firstWeekday, id: \.self) { _ in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
            }

            // Day cells
            ForEach(Array(days.enumerated()), id: \.element) { index, date in
                let day = calendar.component(.day, from: date)
                let summary = viewModel.summary(for: day)
                let recurringSummary = viewModel.recurringSummary(for: day)
                let combinedPriority = viewModel.combinedPriority(for: day)

                CalendarDayCell(
                    day: day,
                    isToday: viewModel.isToday(date),
                    isSelected: viewModel.isSelected(date),
                    summary: summary,
                    recurringSummary: recurringSummary,
                    combinedPriority: combinedPriority,
                    showRecurringOnly: viewModel.showRecurringOnly
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.selectDate(date)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Selected Day Section

    @ViewBuilder
    private func selectedDaySection(viewModel: CalendarViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let selectedDate = viewModel.selectedDate {
                let documents = viewModel.selectedDayDocuments
                let recurringInstances = viewModel.selectedDayRecurringInstances

                // Header card
                HStack {
                    Text(formattedDate(selectedDate))
                        .font(Typography.headline)

                    Spacer()

                    if viewModel.selectedDayTotalCount > 0 {
                        Text(String.localized(L10n.CalendarView.documentsCount, with: viewModel.selectedDayTotalCount))
                            .font(Typography.caption1.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(
                                Capsule()
                                    .fill(AppColors.primary)
                            )
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)

                if documents.isEmpty && recurringInstances.isEmpty {
                    emptyDayView
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.sm) {
                            // Recurring instances section
                            if !recurringInstances.isEmpty {
                                recurringInstancesSection(
                                    instances: recurringInstances,
                                    viewModel: viewModel
                                )
                            }

                            // Documents section (if not showing recurring only)
                            if !documents.isEmpty && !viewModel.showRecurringOnly {
                                documentsSection(documents: documents)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.md)
                        .padding(.bottom, Spacing.xxl)
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                selectDayPrompt
            }
        }
        .frame(maxHeight: .infinity)
        .background {
            // PERFORMANCE: Uses CardMaterial for optimized single-layer blur
            CardMaterial(cornerRadius: CornerRadius.xl)
                .overlay { GlassBorder(cornerRadius: CornerRadius.xl) }
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: -4)
        }
        .navigationDestination(for: FinanceDocument.self) { document in
            DocumentDetailView(documentId: document.id)
                .environment(environment)
        }
        .sheet(isPresented: $showingRecurringDeletionSheet) {
            if let deletionVM = recurringDeletionViewModel {
                RecurringInstanceDeletionSheet(viewModel: deletionVM) { result in
                    // Refresh calendar after deletion
                    if result.success {
                        showingRecurringDeletionSheet = false
                        Task {
                            await self.viewModel?.loadDocuments()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recurring Instances Section

    @ViewBuilder
    private func recurringInstancesSection(instances: [RecurringInstance], viewModel: CalendarViewModel) -> some View {
        Section {
            ForEach(instances) { instance in
                RecurringInstanceRow(
                    instance: instance,
                    onMarkAsPaid: {
                        Task {
                            await viewModel.markInstanceAsPaid(instance)
                        }
                    },
                    onViewDocument: instance.matchedDocumentId,
                    onDelete: {
                        handleInstanceDelete(instance)
                    }
                )
            }
        } header: {
            if !viewModel.showRecurringOnly {
                Text(L10n.CalendarView.recurringSection.localized)
                    .font(Typography.caption1.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Instance Delete Handler

    private func handleInstanceDelete(_ instance: RecurringInstance) {
        let deletionVM = environment.makeRecurringDeletionViewModel()
        recurringDeletionViewModel = deletionVM
        instanceToDelete = instance

        Task {
            await deletionVM.setupForInstanceDeletion(instance: instance, template: nil)
            showingRecurringDeletionSheet = true
        }
    }

    // MARK: - Documents Section

    @ViewBuilder
    private func documentsSection(documents: [FinanceDocument]) -> some View {
        Section {
            ForEach(documents) { document in
                NavigationLink(value: document) {
                    DocumentRow(document: document) {}
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(L10n.CalendarView.documentsSection.localized)
                .font(Typography.caption1.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Empty State Views

    private var emptyDayView: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text(L10n.CalendarView.noDocuments.localized)
                .font(Typography.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    private var selectDayPrompt: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.primary.opacity(0.5))

            Text(L10n.CalendarView.documentsDue.localized)
                .font(Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func setupViewModel() {
        guard viewModel == nil else { return }
        viewModel = CalendarViewModel(
            fetchDocumentsUseCase: environment.makeFetchDocumentsForCalendarUseCase(),
            fetchRecurringInstancesUseCase: environment.makeFetchRecurringInstancesForMonthUseCase(),
            recurringSchedulerService: environment.recurringSchedulerService
        )
    }
}

// MARK: - Calendar Day Cell

struct CalendarDayCell: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let day: Int
    let isToday: Bool
    let isSelected: Bool
    let summary: CalendarDaySummary?
    let recurringSummary: CalendarRecurringSummary?
    let combinedPriority: CalendarCombinedPriority
    let showRecurringOnly: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Background with modern styling
                if isSelected {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(
                            LinearGradient(
                                colors: [AppColors.primary, AppColors.primary.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: AppColors.primary.opacity(0.4), radius: 6, y: 3)
                } else if isToday {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(AppColors.primary.opacity(0.15))
                        .overlay {
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .strokeBorder(AppColors.primary.opacity(0.5), lineWidth: 1.5)
                        }
                } else if !reduceTransparency {
                    // PERFORMANCE: Removed .ultraThinMaterial for non-selected cells
                    // Day cells don't need blur effect - reduces GPU load significantly
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(Color.white.opacity(colorScheme == .light ? 0.3 : 0.05))
                }

                // Day number and indicator
                VStack(spacing: 3) {
                    Text("\(day)")
                        .font(isToday || isSelected ? Typography.bodyBold : Typography.body)
                        .foregroundStyle(textColor)

                    // Indicator dots
                    HStack(spacing: 2) {
                        // Document indicator
                        if !showRecurringOnly, let summary = summary, summary.totalCount > 0 {
                            Circle()
                                .fill(indicatorColor(for: summary.priority))
                                .frame(width: 5, height: 5)
                        }

                        // Recurring indicator
                        if let recurringSummary = recurringSummary, recurringSummary.totalCount > 0 {
                            Circle()
                                .fill(recurringIndicatorColor(for: recurringSummary.priority))
                                .frame(width: 5, height: 5)
                                .overlay {
                                    // Dotted border for expected instances
                                    if recurringSummary.expectedCount > 0 {
                                        Circle()
                                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                            .foregroundStyle(recurringIndicatorColor(for: recurringSummary.priority))
                                            .frame(width: 7, height: 7)
                                    }
                                }
                        }
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !reduceMotion && !isPressed {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    if !reduceMotion {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                            isPressed = false
                        }
                    }
                }
        )
    }

    private var textColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return AppColors.primary
        } else {
            return .primary
        }
    }

    private func indicatorColor(for priority: CalendarDayPriority) -> Color {
        switch priority {
        case .overdue:
            return AppColors.error
        case .scheduled:
            return AppColors.warning
        case .draft:
            return .gray
        case .paid:
            return AppColors.success
        }
    }

    private func recurringIndicatorColor(for priority: CalendarRecurringPriority) -> Color {
        switch priority {
        case .overdue:
            return AppColors.error
        case .expected:
            return AppColors.primary  // Blue for expected
        case .matched:
            return AppColors.warning  // Orange for matched
        case .paid:
            return AppColors.success
        case .missed:
            return .gray
        }
    }
}

// MARK: - Recurring Instance Row

struct RecurringInstanceRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let instance: RecurringInstance
    let onMarkAsPaid: () -> Void
    let onViewDocument: UUID?
    let onDelete: () -> Void

    @State private var vendorName: String = ""
    @State private var showingActions = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Status icon
            statusIcon

            // Content
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack {
                    Text(vendorName.isEmpty ? L10n.CalendarView.expectedPayment.localized : vendorName)
                        .font(Typography.body)
                        .lineLimit(1)

                    Spacer()

                    // Status badge
                    statusBadge
                }

                // Amount and due info
                HStack {
                    if let amount = instance.effectiveAmount {
                        Text(formatAmount(amount))
                            .font(Typography.caption1.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    dueLabel
                }
            }
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(backgroundColor)
                .overlay {
                    // Dotted border for expected instances
                    if instance.status == .expected {
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                            .foregroundStyle(AppColors.primary.opacity(0.5))
                    } else {
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingActions = true
        }
        .confirmationDialog(
            L10n.CalendarView.expectedPayment.localized,
            isPresented: $showingActions,
            titleVisibility: .visible
        ) {
            if instance.status == .expected || instance.status == .matched {
                Button(L10n.CalendarView.markAsPaid.localized) {
                    onMarkAsPaid()
                }
            }
            if let _ = onViewDocument {
                Button(L10n.CalendarView.viewDocument.localized) {
                    // Navigation handled by parent
                }
            }
            // Delete option - opens the recurring instance deletion sheet
            Button(L10n.Common.delete.localized, role: .destructive) {
                onDelete()
            }
            Button(L10n.Common.cancel.localized, role: .cancel) {}
        }
    }

    private var statusIcon: some View {
        Image(systemName: instance.status.iconName)
            .font(.title3)
            .foregroundStyle(statusColor)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(statusColor.opacity(0.15))
            )
    }

    private var statusBadge: some View {
        Text(instance.status.displayName)
            .font(Typography.caption2.weight(.medium))
            .foregroundStyle(statusColor)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule()
                    .fill(statusColor.opacity(0.15))
            )
    }

    private var dueLabel: some View {
        Group {
            let days = instance.daysUntilDue
            if days == 0 {
                Text(L10n.RecurringInstance.dueToday.localized)
                    .foregroundStyle(AppColors.warning)
            } else if days < 0 {
                Text(String.localized(L10n.RecurringInstance.overdue, with: abs(days)))
                    .foregroundStyle(AppColors.error)
            } else {
                Text(String.localized(L10n.RecurringInstance.dueIn, with: days))
                    .foregroundStyle(.secondary)
            }
        }
        .font(Typography.caption1)
    }

    private var statusColor: Color {
        switch instance.status {
        case .expected:
            return AppColors.primary
        case .matched:
            return AppColors.warning
        case .paid:
            return AppColors.success
        case .missed:
            return AppColors.error
        case .cancelled:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        colorScheme == .light
            ? Color.white.opacity(0.6)
            : Color.white.opacity(0.05)
    }

    private var borderColor: Color {
        statusColor.opacity(0.3)
    }

    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "PLN"
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - Preview

#Preview {
    CalendarView()
        .environment(AppEnvironment.preview)
}
