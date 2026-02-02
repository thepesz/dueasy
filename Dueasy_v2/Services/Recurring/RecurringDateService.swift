import Foundation
import os.log

/// Service for date calculations related to recurring payments.
/// Provides consistent timezone handling (Europe/Warsaw) across the app
/// to ensure period keys remain stable regardless of device timezone changes.
///
/// MVVM Compliance: This service extracts business logic that was previously
/// embedded in RecurringInstance (@Model), maintaining clean separation where
/// models are "dumb" data containers and services handle business logic.
///
/// Thread Safety: All methods are pure functions operating on input data,
/// making this service inherently thread-safe.
protocol RecurringDateServiceProtocol: Sendable {

    /// The fixed timezone calendar used for all date calculations.
    /// Uses Europe/Warsaw to ensure period keys are consistent across timezone changes.
    var calendar: Calendar { get }

    /// Generates a period key from a date.
    /// - Parameter date: The date to generate a period key for
    /// - Returns: Period key in format "YYYY-MM" (e.g., "2026-02")
    func periodKey(for date: Date) -> String

    /// Generates the expected due date for a given period and day of month.
    /// - Parameters:
    ///   - periodKey: Period key in format "YYYY-MM"
    ///   - dayOfMonth: Day of month (1-31), clamped to valid days for the month
    /// - Returns: The expected due date, or nil if period key is invalid
    func expectedDueDate(periodKey: String, dayOfMonth: Int) -> Date?

    /// Extracts year and month from a period key.
    /// - Parameter periodKey: Period key in format "YYYY-MM"
    /// - Returns: Tuple of (year, month), or nil if period key is invalid
    func yearMonth(from periodKey: String) -> (year: Int, month: Int)?

    /// Calculates the number of days between two dates.
    /// - Parameters:
    ///   - fromDate: Start date
    ///   - toDate: End date
    /// - Returns: Number of days (negative if toDate is before fromDate)
    func daysBetween(from fromDate: Date, to toDate: Date) -> Int

    /// Returns the number of days in a given month.
    /// - Parameters:
    ///   - year: Year (e.g., 2026)
    ///   - month: Month (1-12)
    /// - Returns: Number of days in the month
    func daysInMonth(year: Int, month: Int) -> Int

    /// Returns the start of day for a given date.
    /// - Parameter date: The date
    /// - Returns: Start of day in the fixed timezone
    func startOfDay(for date: Date) -> Date

    /// Adds months to a date.
    /// - Parameters:
    ///   - months: Number of months to add (can be negative)
    ///   - date: Base date
    /// - Returns: Resulting date, or nil if calculation fails
    func addMonths(_ months: Int, to date: Date) -> Date?

    /// Adds days to a date.
    /// - Parameters:
    ///   - days: Number of days to add (can be negative)
    ///   - date: Base date
    /// - Returns: Resulting date, or nil if calculation fails
    func addDays(_ days: Int, to date: Date) -> Date?

    /// Extracts date components from a date.
    /// - Parameters:
    ///   - components: Components to extract
    ///   - date: The date
    /// - Returns: DateComponents with requested values
    func dateComponents(_ components: Set<Calendar.Component>, from date: Date) -> DateComponents
}

/// Default implementation of RecurringDateService.
/// Uses Europe/Warsaw timezone to ensure consistent period key generation
/// regardless of device timezone or user travel.
final class RecurringDateService: RecurringDateServiceProtocol, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "RecurringDate")

    // MARK: - Fixed Timezone Calendar

    /// Fixed timezone calendar for period key calculations.
    /// CRITICAL: Uses Europe/Warsaw timezone to prevent period key inconsistency
    /// when user travels or device timezone changes.
    /// All recurring payment date calculations MUST use this calendar.
    let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        // Use fixed timezone to ensure period keys are consistent regardless of device timezone
        cal.timeZone = TimeZone(identifier: "Europe/Warsaw") ?? TimeZone(identifier: "UTC")!
        return cal
    }()

    // MARK: - Initialization

    init() {
        // Log timezone for debugging (safe - no PII)
        logger.debug("RecurringDateService initialized with timezone: \(self.calendar.timeZone.identifier)")
    }

    // MARK: - Period Key Generation

    func periodKey(for date: Date) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return String(format: "%04d-%02d", year, month)
    }

    // MARK: - Expected Due Date Calculation

    func expectedDueDate(periodKey: String, dayOfMonth: Int) -> Date? {
        guard let (year, month) = yearMonth(from: periodKey) else {
            logger.warning("Invalid period key format: expected YYYY-MM")
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = min(dayOfMonth, daysInMonth(year: year, month: month))

        return calendar.date(from: components)
    }

    // MARK: - Period Key Parsing

    func yearMonth(from periodKey: String) -> (year: Int, month: Int)? {
        let parts = periodKey.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              month >= 1, month <= 12 else {
            return nil
        }
        return (year, month)
    }

    // MARK: - Date Calculations

    func daysBetween(from fromDate: Date, to toDate: Date) -> Int {
        let fromStart = startOfDay(for: fromDate)
        let toStart = startOfDay(for: toDate)
        let components = calendar.dateComponents([.day], from: fromStart, to: toStart)
        return components.day ?? 0
    }

    func daysInMonth(year: Int, month: Int) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month + 1
        components.day = 0

        guard let date = calendar.date(from: components) else {
            return 28 // Fallback for invalid dates
        }

        return calendar.component(.day, from: date)
    }

    func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func addMonths(_ months: Int, to date: Date) -> Date? {
        calendar.date(byAdding: .month, value: months, to: date)
    }

    func addDays(_ days: Int, to date: Date) -> Date? {
        calendar.date(byAdding: .day, value: days, to: date)
    }

    func dateComponents(_ components: Set<Calendar.Component>, from date: Date) -> DateComponents {
        calendar.dateComponents(components, from: date)
    }
}
