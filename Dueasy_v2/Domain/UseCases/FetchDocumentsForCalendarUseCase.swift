import Foundation

/// Use case for fetching documents within a date range for calendar display.
/// Groups documents by their due date for efficient calendar rendering.
struct FetchDocumentsForCalendarUseCase: Sendable {

    private let repository: DocumentRepositoryProtocol

    init(repository: DocumentRepositoryProtocol) {
        self.repository = repository
    }

    /// Fetches all documents with due dates in the specified month.
    /// - Parameters:
    ///   - month: The month to fetch documents for (1-12)
    ///   - year: The year to fetch documents for
    /// - Returns: Dictionary mapping day-of-month to documents due on that day
    @MainActor
    func execute(month: Int, year: Int) async throws -> [Int: [FinanceDocument]] {
        let calendar = Calendar.current

        // Calculate start and end of month
        guard let startOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) else {
            return [:]
        }

        // Use end of day for endOfMonth to include documents due on the last day
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endOfMonth) ?? endOfMonth

        // Fetch documents within the date range
        let documents = try await repository.fetch(dueDateBetween: startOfMonth, and: endOfDay)

        // Group by day of month
        var grouped: [Int: [FinanceDocument]] = [:]

        for document in documents {
            guard let dueDate = document.dueDate else { continue }
            let day = calendar.component(.day, from: dueDate)

            if grouped[day] == nil {
                grouped[day] = []
            }
            grouped[day]?.append(document)
        }

        return grouped
    }

    /// Fetches documents for a given date range (more flexible version).
    /// - Parameters:
    ///   - startDate: Start of the date range
    ///   - endDate: End of the date range
    /// - Returns: Array of documents with due dates in the range
    @MainActor
    func execute(from startDate: Date, to endDate: Date) async throws -> [FinanceDocument] {
        return try await repository.fetch(dueDateBetween: startDate, and: endDate)
    }

    /// Gets count of documents per day for a month (for badge display).
    /// - Parameters:
    ///   - month: The month (1-12)
    ///   - year: The year
    /// - Returns: Dictionary mapping day-of-month to document count
    @MainActor
    func countsByDay(month: Int, year: Int) async throws -> [Int: Int] {
        let grouped = try await execute(month: month, year: year)
        return grouped.mapValues { $0.count }
    }

    /// Gets summary information for calendar badges (count and urgency).
    /// - Parameters:
    ///   - month: The month (1-12)
    ///   - year: The year
    /// - Returns: Dictionary mapping day-of-month to CalendarDaySummary
    @MainActor
    func summaryByDay(month: Int, year: Int) async throws -> [Int: CalendarDaySummary] {
        let grouped = try await execute(month: month, year: year)

        return grouped.mapValues { documents in
            let overdueCount = documents.filter { $0.isOverdue }.count
            let scheduledCount = documents.filter { $0.status == .scheduled }.count
            let paidCount = documents.filter { $0.status == .paid }.count
            let draftCount = documents.filter { $0.status == .draft }.count

            // Determine priority: overdue > scheduled > draft > paid
            let priority: CalendarDayPriority
            if overdueCount > 0 {
                priority = .overdue
            } else if scheduledCount > 0 {
                priority = .scheduled
            } else if draftCount > 0 {
                priority = .draft
            } else {
                priority = .paid
            }

            return CalendarDaySummary(
                totalCount: documents.count,
                overdueCount: overdueCount,
                scheduledCount: scheduledCount,
                paidCount: paidCount,
                draftCount: draftCount,
                priority: priority
            )
        }
    }
}

// MARK: - Supporting Types

/// Summary of documents for a single calendar day.
struct CalendarDaySummary {
    let totalCount: Int
    let overdueCount: Int
    let scheduledCount: Int
    let paidCount: Int
    let draftCount: Int
    let priority: CalendarDayPriority
}

/// Priority level for calendar day display.
/// Determines the badge color for days with multiple documents.
enum CalendarDayPriority {
    case overdue    // Red - highest priority
    case scheduled  // Orange - pending action
    case draft      // Gray - needs review
    case paid       // Green - completed
}
