import Foundation

/// Protocol for calendar integration.
/// Iteration 1: EventKit local calendar.
/// Iteration 2: Same implementation (calendar is always local).
protocol CalendarServiceProtocol: Sendable {

    /// Current authorization status.
    var authorizationStatus: CalendarAuthorizationStatus { get async }

    /// Requests calendar access from the user.
    /// - Returns: Whether access was granted
    func requestAccess() async -> Bool

    /// Creates a calendar event for a document due date.
    /// - Parameters:
    ///   - title: Event title (e.g., "Invoice: Vendor Name - $100")
    ///   - dueDate: Due date for the event
    ///   - notes: Optional notes for the event
    ///   - calendarId: Optional specific calendar ID (uses default if nil)
    /// - Returns: Created event identifier
    /// - Throws: `AppError.calendarEventCreationFailed`, `AppError.calendarPermissionDenied`
    func createEvent(
        title: String,
        dueDate: Date,
        notes: String?,
        calendarId: String?
    ) async throws -> String

    /// Updates an existing calendar event.
    /// - Parameters:
    ///   - eventId: Existing event identifier
    ///   - title: New title
    ///   - dueDate: New due date
    ///   - notes: New notes
    /// - Throws: `AppError.calendarEventUpdateFailed`
    func updateEvent(
        eventId: String,
        title: String,
        dueDate: Date,
        notes: String?
    ) async throws

    /// Deletes a calendar event.
    /// - Parameter eventId: Event identifier to delete
    /// - Throws: `AppError.calendarEventDeletionFailed`
    func deleteEvent(eventId: String) async throws

    /// Gets available calendars for event creation.
    /// - Returns: List of available calendars
    func getAvailableCalendars() async -> [CalendarInfo]

    /// Creates a dedicated "Invoices" calendar if it doesn't exist.
    /// - Returns: Calendar identifier
    func getOrCreateInvoicesCalendar() async throws -> String

    /// Gets the default calendar for events.
    /// - Returns: Default calendar identifier, or nil if none available
    func getDefaultCalendarId() async -> String?
}

/// Calendar authorization status
enum CalendarAuthorizationStatus: Sendable {
    case notDetermined
    case restricted
    case denied
    case fullAccess
    case writeOnly

    var hasWriteAccess: Bool {
        self == .fullAccess || self == .writeOnly
    }
}

/// Information about an available calendar
struct CalendarInfo: Identifiable, Sendable {
    let id: String
    let title: String
    let isDefault: Bool
    let color: String? // Hex color string
}
