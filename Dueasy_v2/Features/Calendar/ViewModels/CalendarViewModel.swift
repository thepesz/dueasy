import Foundation
import Observation
import os.log

/// ViewModel for the calendar screen.
/// Manages month navigation, document fetching, recurring instance display, and day selection.
@MainActor
@Observable
final class CalendarViewModel {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "CalendarViewModel")

    // MARK: - State

    private(set) var currentMonth: Date = Date()
    private(set) var selectedDate: Date?
    private(set) var documentsByDay: [Int: [FinanceDocument]] = [:]
    private(set) var summaryByDay: [Int: CalendarDaySummary] = [:]
    private(set) var recurringByDay: [Int: [RecurringInstance]] = [:]
    private(set) var recurringSummaryByDay: [Int: CalendarRecurringSummary] = [:]
    private(set) var isLoading = false
    private(set) var error: AppError?

    /// Filter to show only recurring payments
    var showRecurringOnly = false

    // MARK: - Dependencies

    private let fetchDocumentsUseCase: FetchDocumentsForCalendarUseCase
    private let fetchRecurringInstancesUseCase: FetchRecurringInstancesForMonthUseCase
    private let recurringSchedulerService: RecurringSchedulerServiceProtocol

    // MARK: - Computed Properties

    var currentMonthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: currentMonth).capitalized
    }

    var currentYear: Int {
        Calendar.current.component(.year, from: currentMonth)
    }

    var currentMonthNumber: Int {
        Calendar.current.component(.month, from: currentMonth)
    }

    var daysInMonth: [Date] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let monthRange = calendar.range(of: .day, in: .month, for: currentMonth) else {
            return []
        }

        return monthRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start)
        }
    }

    var firstWeekdayOfMonth: Int {
        let calendar = Calendar.current
        guard let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) else {
            return 0
        }
        // Adjust for week starting on Monday (1) vs Sunday (0)
        let weekday = calendar.component(.weekday, from: firstDay)
        // Convert to Monday-based (0 = Monday, 6 = Sunday)
        return (weekday + 5) % 7
    }

    var selectedDayDocuments: [FinanceDocument] {
        guard !showRecurringOnly else { return [] }
        guard let selectedDate = selectedDate else { return [] }
        let day = Calendar.current.component(.day, from: selectedDate)
        return documentsByDay[day] ?? []
    }

    var selectedDayRecurringInstances: [RecurringInstance] {
        guard let selectedDate = selectedDate else { return [] }
        let day = Calendar.current.component(.day, from: selectedDate)
        return recurringByDay[day] ?? []
    }

    /// Combined item count for selected day (documents + non-matched recurring instances)
    var selectedDayTotalCount: Int {
        let docCount = selectedDayDocuments.count
        // Only count recurring instances that are NOT matched (to avoid double counting)
        let recurringCount = selectedDayRecurringInstances.filter { $0.status != .matched }.count
        return docCount + recurringCount
    }

    var isCurrentMonth: Bool {
        let calendar = Calendar.current
        return calendar.isDate(currentMonth, equalTo: Date(), toGranularity: .month)
    }

    // MARK: - Initialization

    init(
        fetchDocumentsUseCase: FetchDocumentsForCalendarUseCase,
        fetchRecurringInstancesUseCase: FetchRecurringInstancesForMonthUseCase,
        recurringSchedulerService: RecurringSchedulerServiceProtocol
    ) {
        self.fetchDocumentsUseCase = fetchDocumentsUseCase
        self.fetchRecurringInstancesUseCase = fetchRecurringInstancesUseCase
        self.recurringSchedulerService = recurringSchedulerService
    }

    // MARK: - Actions

    func loadDocuments() async {
        isLoading = true
        error = nil

        logger.info("📅 CalendarViewModel.loadDocuments() called for month: \(self.currentMonthNumber), year: \(self.currentYear)")

        do {
            // Fetch documents
            documentsByDay = try await fetchDocumentsUseCase.execute(
                month: currentMonthNumber,
                year: currentYear
            )
            summaryByDay = try await fetchDocumentsUseCase.summaryByDay(
                month: currentMonthNumber,
                year: currentYear
            )

            logger.info("📅 Fetched \(self.documentsByDay.values.flatMap { $0 }.count) documents for calendar")

            // Fetch recurring instances
            recurringByDay = try await fetchRecurringInstancesUseCase.execute(
                month: currentMonthNumber,
                year: currentYear
            )
            recurringSummaryByDay = try await fetchRecurringInstancesUseCase.summaryByDay(
                month: currentMonthNumber,
                year: currentYear
            )

            let totalRecurringInstances = recurringByDay.values.flatMap { $0 }.count
            logger.info("📅 Fetched \(totalRecurringInstances) recurring instances for calendar")
            logger.info("📅 Recurring instances by day: \(self.recurringByDay.keys.sorted().map { "Day \($0): \(self.recurringByDay[$0]?.count ?? 0)" }.joined(separator: ", "))")

        } catch let appError as AppError {
            error = appError
            logger.error("📅 CalendarViewModel error: \(appError.localizedDescription)")
        } catch {
            self.error = .repositoryFetchFailed(error.localizedDescription)
            logger.error("📅 CalendarViewModel error: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func selectDate(_ date: Date) {
        selectedDate = date
    }

    func clearSelection() {
        selectedDate = nil
    }

    func goToPreviousMonth() {
        let calendar = Calendar.current
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = newMonth
            selectedDate = nil
            Task {
                await loadDocuments()
            }
        }
    }

    func goToNextMonth() {
        let calendar = Calendar.current
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newMonth
            selectedDate = nil
            Task {
                await loadDocuments()
            }
        }
    }

    func goToToday() {
        currentMonth = Date()
        selectedDate = Date()
        Task {
            await loadDocuments()
        }
    }

    func clearError() {
        error = nil
    }

    // MARK: - Recurring Instance Actions

    /// Marks a recurring instance as paid
    func markInstanceAsPaid(_ instance: RecurringInstance) async {
        do {
            try await recurringSchedulerService.markInstanceAsPaid(instance)
            // Reload to refresh the UI
            await loadDocuments()
        } catch {
            self.error = .repositoryFetchFailed("Failed to mark as paid: \(error.localizedDescription)")
        }
    }

    /// Fetches the template for a recurring instance
    func fetchTemplate(for instance: RecurringInstance) async -> RecurringTemplate? {
        do {
            return try await fetchRecurringInstancesUseCase.fetchTemplate(byId: instance.templateId)
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    func isSelected(_ date: Date) -> Bool {
        guard let selectedDate = selectedDate else { return false }
        return Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    func summary(for day: Int) -> CalendarDaySummary? {
        summaryByDay[day]
    }

    func recurringSummary(for day: Int) -> CalendarRecurringSummary? {
        recurringSummaryByDay[day]
    }

    func documents(for day: Int) -> [FinanceDocument] {
        documentsByDay[day] ?? []
    }

    func recurringInstances(for day: Int) -> [RecurringInstance] {
        recurringByDay[day] ?? []
    }

    /// Returns true if this day has any items to display (considering the filter)
    func hasItems(for day: Int) -> Bool {
        if showRecurringOnly {
            return (recurringSummaryByDay[day]?.totalCount ?? 0) > 0
        }
        let docCount = summaryByDay[day]?.totalCount ?? 0
        let recurringCount = recurringSummaryByDay[day]?.totalCount ?? 0
        return docCount > 0 || recurringCount > 0
    }

    /// Combined priority for a day (highest priority wins)
    func combinedPriority(for day: Int) -> CalendarCombinedPriority {
        let docSummary = summaryByDay[day]
        let recurringSummary = recurringSummaryByDay[day]

        // Check overdue first (highest priority)
        if docSummary?.overdueCount ?? 0 > 0 || recurringSummary?.overdueCount ?? 0 > 0 {
            return .overdue
        }

        // Then scheduled/expected
        if docSummary?.scheduledCount ?? 0 > 0 {
            return .scheduled
        }
        if recurringSummary?.expectedCount ?? 0 > 0 {
            return .expected
        }

        // Then matched recurring
        if recurringSummary?.matchedCount ?? 0 > 0 {
            return .matched
        }

        // Then draft documents
        if docSummary?.draftCount ?? 0 > 0 {
            return .draft
        }

        // Then paid
        if docSummary?.paidCount ?? 0 > 0 || recurringSummary?.paidCount ?? 0 > 0 {
            return .paid
        }

        // Default
        return .none
    }
}

// MARK: - Combined Priority

/// Combined priority for calendar display that considers both documents and recurring instances.
enum CalendarCombinedPriority: Sendable {
    case overdue    // Red - highest priority
    case scheduled  // Orange - document scheduled
    case expected   // Blue - recurring expected
    case matched    // Orange-blue - recurring matched
    case draft      // Gray - needs review
    case paid       // Green - completed
    case none       // No items
}
