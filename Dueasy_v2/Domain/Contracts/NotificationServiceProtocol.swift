import Foundation

/// Protocol for local notification scheduling.
/// Iteration 1 & 2: Local notifications (always on-device).
protocol NotificationServiceProtocol: Sendable {

    /// Current authorization status.
    var authorizationStatus: NotificationAuthorizationStatus { get async }

    /// Requests notification permission from the user.
    /// - Returns: Whether permission was granted
    func requestAuthorization() async -> Bool

    /// Schedules reminders for a document based on due date and offsets.
    /// - Parameters:
    ///   - documentId: Document identifier (used for notification IDs)
    ///   - title: Notification title
    ///   - body: Notification body
    ///   - dueDate: Due date of the document
    ///   - reminderOffsets: Days before due date to send reminders (e.g., [7, 1, 0])
    /// - Returns: Array of scheduled notification identifiers
    /// - Throws: `AppError.notificationSchedulingFailed`
    func scheduleReminders(
        documentId: String,
        title: String,
        body: String,
        dueDate: Date,
        reminderOffsets: [Int]
    ) async throws -> [String]

    /// Cancels all notifications for a document.
    /// - Parameter documentId: Document identifier
    func cancelReminders(forDocumentId documentId: String) async

    /// Cancels specific notifications by their identifiers.
    /// - Parameter notificationIds: Notification identifiers to cancel
    func cancelNotifications(ids: [String]) async

    /// Gets all pending notification identifiers for a document.
    /// - Parameter documentId: Document identifier
    /// - Returns: Array of pending notification identifiers
    func getPendingNotifications(forDocumentId documentId: String) async -> [String]

    /// Updates reminders for a document (cancels existing and schedules new).
    /// - Parameters:
    ///   - documentId: Document identifier
    ///   - title: Notification title
    ///   - body: Notification body
    ///   - dueDate: New due date
    ///   - reminderOffsets: Days before due date to send reminders
    /// - Returns: Array of scheduled notification identifiers
    /// - Throws: `AppError.notificationSchedulingFailed`
    func updateReminders(
        documentId: String,
        title: String,
        body: String,
        dueDate: Date,
        reminderOffsets: [Int]
    ) async throws -> [String]
}

/// Notification authorization status
enum NotificationAuthorizationStatus: Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var isAuthorized: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }
}
