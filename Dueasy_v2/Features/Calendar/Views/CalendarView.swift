import SwiftUI

/// Calendar view showing documents by due date.
/// Uses a month grid with day badges indicating document counts and urgency.
struct CalendarView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel: CalendarViewModel?
    @State private var appeared = false

    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

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
            .navigationTitle(L10n.CalendarView.title.localized)
        }
        .task {
            setupViewModel()
            await viewModel?.loadDocuments()
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.5)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func calendarContent(viewModel: CalendarViewModel) -> some View {
        ZStack {
            // Modern gradient background
            GradientBackground()

            VStack(spacing: 0) {
                // Month navigation header with glass effect
                monthHeader(viewModel: viewModel)

                // Weekday labels
                weekdayLabels

                // Calendar grid
                calendarGrid(viewModel: viewModel)
                    .padding(.bottom, Spacing.md)

                // Selected day documents in glass card
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
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(
                                Color.white.opacity(colorScheme == .light ? 0.5 : 0.1),
                                lineWidth: 0.5
                            )
                    }
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
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(
                                Color.white.opacity(colorScheme == .light ? 0.5 : 0.1),
                                lineWidth: 0.5
                            )
                    }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
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

                CalendarDayCell(
                    day: day,
                    isToday: viewModel.isToday(date),
                    isSelected: viewModel.isSelected(date),
                    summary: summary
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.selectDate(date)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.8)
                .animation(
                    reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.7).delay(Double(index) * 0.01),
                    value: appeared
                )
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

                // Header card
                HStack {
                    Text(formattedDate(selectedDate))
                        .font(Typography.headline)

                    Spacer()

                    if !documents.isEmpty {
                        Text(String.localized(L10n.CalendarView.documentsCount, with: documents.count))
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

                if documents.isEmpty {
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
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.sm) {
                            ForEach(documents) { document in
                                NavigationLink(value: document) {
                                    DocumentRow(document: document) {}
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.md)
                        .padding(.bottom, Spacing.xxl)
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
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
        }
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
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
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: -4)
        }
        .navigationDestination(for: FinanceDocument.self) { document in
            DocumentDetailView(documentId: document.id)
                .environment(environment)
        }
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
            fetchDocumentsUseCase: environment.makeFetchDocumentsForCalendarUseCase()
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
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(.ultraThinMaterial.opacity(0.5))
                }

                // Day number and indicator
                VStack(spacing: 3) {
                    Text("\(day)")
                        .font(isToday || isSelected ? Typography.bodyBold : Typography.body)
                        .foregroundStyle(textColor)

                    // Document indicator with glow
                    if let summary = summary, summary.totalCount > 0 {
                        Circle()
                            .fill(indicatorColor(for: summary.priority))
                            .frame(width: 7, height: 7)
                            .shadow(
                                color: indicatorColor(for: summary.priority).opacity(0.5),
                                radius: 2,
                                y: 1
                            )
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
}

// MARK: - Preview

#Preview {
    CalendarView()
        .environment(AppEnvironment.preview)
}
