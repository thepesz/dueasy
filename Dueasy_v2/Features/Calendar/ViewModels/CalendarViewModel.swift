import Foundation
import Observation

/// ViewModel for the calendar screen.
/// Manages month navigation, document fetching, and day selection.
@MainActor
@Observable
final class CalendarViewModel {

    // MARK: - State

    private(set) var currentMonth: Date = Date()
    private(set) var selectedDate: Date?
    private(set) var documentsByDay: [Int: [FinanceDocument]] = [:]
    private(set) var summaryByDay: [Int: CalendarDaySummary] = [:]
    private(set) var isLoading = false
    private(set) var error: AppError?

    // MARK: - Dependencies

    private let fetchDocumentsUseCase: FetchDocumentsForCalendarUseCase

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
        guard let selectedDate = selectedDate else { return [] }
        let day = Calendar.current.component(.day, from: selectedDate)
        return documentsByDay[day] ?? []
    }

    var isCurrentMonth: Bool {
        let calendar = Calendar.current
        return calendar.isDate(currentMonth, equalTo: Date(), toGranularity: .month)
    }

    // MARK: - Initialization

    init(fetchDocumentsUseCase: FetchDocumentsForCalendarUseCase) {
        self.fetchDocumentsUseCase = fetchDocumentsUseCase
    }

    // MARK: - Actions

    func loadDocuments() async {
        isLoading = true
        error = nil

        do {
            documentsByDay = try await fetchDocumentsUseCase.execute(
                month: currentMonthNumber,
                year: currentYear
            )
            summaryByDay = try await fetchDocumentsUseCase.summaryByDay(
                month: currentMonthNumber,
                year: currentYear
            )
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .repositoryFetchFailed(error.localizedDescription)
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

    func documents(for day: Int) -> [FinanceDocument] {
        documentsByDay[day] ?? []
    }
}
