import Foundation
import SwiftData

/// Represents an expected payment for a specific period of a recurring template.
/// Instances are generated ahead of time (e.g., 3 months) and track whether
/// a document has been matched and whether payment was made.
///
/// Lifecycle:
/// 1. Created as `expected` when template generates future instances
/// 2. Becomes `matched` when a scanned document matches the instance
/// 3. Transitions to `paid` when user marks as paid, or `missed` if deadline passes
@Model
final class RecurringInstance {

    // MARK: - Primary Fields

    /// Unique identifier
    @Attribute(.unique)
    var id: UUID

    /// ID of the parent template
    var templateId: UUID

    /// Period key in format "YYYY-MM" (e.g., "2026-02")
    @Attribute(.spotlight)
    var periodKey: String

    // MARK: - Expected Values

    /// Expected due date based on template rules
    var expectedDueDate: Date

    /// Expected amount (nil if template has no amount learned yet)
    var expectedAmountValue: Double?

    // MARK: - Status

    /// Current status of this instance
    var statusRaw: String

    // MARK: - Matched Document Data

    /// ID of the document matched to this instance (if any)
    var matchedDocumentId: UUID?

    /// Final due date from the matched document
    var finalDueDate: Date?

    /// Final amount from the matched document
    var finalAmountValue: Double?

    /// Invoice number from the matched document
    var invoiceNumber: String?

    /// When the document was matched to this instance
    var matchedAt: Date?

    // MARK: - Notification State

    /// IDs of scheduled notifications for this instance
    var scheduledNotificationIds: [String]

    /// Whether notifications have been scheduled
    var notificationsScheduled: Bool

    // MARK: - Calendar Event State

    /// Calendar event ID (EventKit identifier) if synced to iOS Calendar
    var calendarEventId: String?

    // MARK: - Timestamps

    /// When this instance was created
    var createdAt: Date

    /// When this instance was last updated
    var updatedAt: Date

    // MARK: - Computed Properties

    /// Instance status
    var status: RecurringInstanceStatus {
        get { RecurringInstanceStatus(rawValue: statusRaw) ?? .expected }
        set { statusRaw = newValue.rawValue }
    }

    /// Expected amount as Decimal
    var expectedAmount: Decimal? {
        get {
            guard let value = expectedAmountValue else { return nil }
            return Decimal(value)
        }
        set {
            if let newValue = newValue {
                expectedAmountValue = NSDecimalNumber(decimal: newValue).doubleValue
            } else {
                expectedAmountValue = nil
            }
        }
    }

    /// Final amount as Decimal
    var finalAmount: Decimal? {
        get {
            guard let value = finalAmountValue else { return nil }
            return Decimal(value)
        }
        set {
            if let newValue = newValue {
                finalAmountValue = NSDecimalNumber(decimal: newValue).doubleValue
            } else {
                finalAmountValue = nil
            }
        }
    }

    /// The due date to use (final if matched, expected otherwise)
    var effectiveDueDate: Date {
        finalDueDate ?? expectedDueDate
    }

    /// The amount to use (final if matched, expected otherwise)
    var effectiveAmount: Decimal? {
        finalAmount ?? expectedAmount
    }

    /// Whether this instance is overdue (expected due date has passed without being matched or paid)
    var isOverdue: Bool {
        guard status == .expected || status == .matched else { return false }
        return effectiveDueDate < Date()
    }

    /// Days until due date (negative if overdue)
    var daysUntilDue: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: effectiveDueDate))
        return components.day ?? 0
    }

    /// Year-month extracted from period key
    var yearMonth: (year: Int, month: Int)? {
        let parts = periodKey.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return nil
        }
        return (year, month)
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        templateId: UUID,
        periodKey: String,
        expectedDueDate: Date,
        expectedAmount: Decimal? = nil,
        status: RecurringInstanceStatus = .expected
    ) {
        self.id = id
        self.templateId = templateId
        self.periodKey = periodKey
        self.expectedDueDate = expectedDueDate
        self.expectedAmountValue = expectedAmount != nil ? NSDecimalNumber(decimal: expectedAmount!).doubleValue : nil
        self.statusRaw = status.rawValue
        self.matchedDocumentId = nil
        self.finalDueDate = nil
        self.finalAmountValue = nil
        self.invoiceNumber = nil
        self.matchedAt = nil
        self.scheduledNotificationIds = []
        self.notificationsScheduled = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Update Methods

    /// Marks the instance as updated
    func markUpdated() {
        updatedAt = Date()
    }

    /// Matches a document to this instance
    func matchDocument(
        documentId: UUID,
        dueDate: Date,
        amount: Decimal?,
        invoiceNumber: String?
    ) {
        self.matchedDocumentId = documentId
        self.finalDueDate = dueDate
        if let amount = amount {
            self.finalAmount = amount
        }
        self.invoiceNumber = invoiceNumber
        self.matchedAt = Date()
        self.status = .matched
        markUpdated()
    }

    /// Marks the instance as paid
    func markAsPaid() {
        self.status = .paid
        markUpdated()
    }

    /// Marks the instance as missed
    func markAsMissed() {
        self.status = .missed
        markUpdated()
    }

    /// Updates notification IDs after scheduling
    func updateNotificationIds(_ ids: [String]) {
        self.scheduledNotificationIds = ids
        self.notificationsScheduled = !ids.isEmpty
        markUpdated()
    }

    /// Clears notification IDs after cancellation
    func clearNotificationIds() {
        self.scheduledNotificationIds = []
        self.notificationsScheduled = false
        markUpdated()
    }

    /// Updates calendar event ID after syncing to iOS Calendar
    func updateCalendarEventId(_ eventId: String) {
        self.calendarEventId = eventId
        markUpdated()
    }

    /// Clears calendar event ID after deletion
    func clearCalendarEventId() {
        self.calendarEventId = nil
        markUpdated()
    }

    /// Unlinks a matched document from this instance, reverting to expected status.
    /// This is used when deleting a document that was matched to a recurring instance.
    func unlinkDocument() {
        self.matchedDocumentId = nil
        self.finalDueDate = nil
        self.finalAmountValue = nil
        self.invoiceNumber = nil
        self.matchedAt = nil
        self.status = .expected
        markUpdated()
    }

    /// Marks the instance as cancelled (soft delete).
    /// The instance remains in database for statistics but is no longer active.
    func markAsCancelled() {
        self.status = .cancelled
        markUpdated()
    }

    // MARK: - Period Key Generation

    /// Generates a period key from a date
    static func periodKey(for date: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return String(format: "%04d-%02d", year, month)
    }

    /// Generates the expected due date for a given period and day of month
    static func expectedDueDate(periodKey: String, dayOfMonth: Int) -> Date? {
        let parts = periodKey.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = min(dayOfMonth, daysInMonth(year: year, month: month))

        return Calendar.current.date(from: components)
    }

    /// Returns the number of days in a given month
    private static func daysInMonth(year: Int, month: Int) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month + 1
        components.day = 0

        guard let date = Calendar.current.date(from: components) else {
            return 28 // Fallback
        }

        return Calendar.current.component(.day, from: date)
    }
}

// MARK: - Recurring Instance Status

/// Status of a recurring instance
enum RecurringInstanceStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Awaiting document - no document matched yet
    case expected

    /// Document matched but not yet marked as paid
    case matched

    /// Payment completed
    case paid

    /// Deadline passed without payment
    case missed

    /// Manually cancelled by user (soft delete)
    case cancelled

    var id: String { rawValue }

    /// Display name for UI (localized)
    var displayName: String {
        L10n.RecurringInstance.status(for: self).localized
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .expected:
            return "clock"
        case .matched:
            return "doc.badge.clock"
        case .paid:
            return "checkmark.circle.fill"
        case .missed:
            return "exclamationmark.triangle.fill"
        case .cancelled:
            return "xmark.circle"
        }
    }

    /// Whether this status represents an active instance that should be shown in calendar
    var isActive: Bool {
        switch self {
        case .expected, .matched:
            return true
        case .paid, .missed, .cancelled:
            return false
        }
    }
}
