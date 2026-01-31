import Foundation
import EventKit
import UIKit
import os.log

/// Calendar service using EventKit.
/// Manages calendar events for document due dates.
final class EventKitCalendarService: CalendarServiceProtocol, @unchecked Sendable {

    private let eventStore = EKEventStore()
    private let logger = Logger(subsystem: "com.dueasy.app", category: "Calendar")

    // MARK: - CalendarServiceProtocol

    var authorizationStatus: CalendarAuthorizationStatus {
        get async {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .notDetermined:
                return .notDetermined
            case .restricted:
                return .restricted
            case .denied:
                return .denied
            case .fullAccess:
                return .fullAccess
            case .writeOnly:
                return .writeOnly
            @unknown default:
                return .denied
            }
        }
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            logger.info("Calendar access request result: \(granted)")
            return granted
        } catch {
            logger.error("Calendar access request failed: \(error.localizedDescription)")
            return false
        }
    }

    func createEvent(
        title: String,
        dueDate: Date,
        notes: String?,
        calendarId: String?
    ) async throws -> String {
        logger.info("Creating calendar event: title='\(title)', dueDate=\(dueDate), calendarId=\(calendarId ?? "default")")

        let status = await authorizationStatus
        logger.info("Calendar authorization status: \(String(describing: status))")

        guard status.hasWriteAccess else {
            logger.error("Calendar permission denied - status does not have write access")
            throw AppError.calendarPermissionDenied
        }

        // Find the calendar to use
        var calendar: EKCalendar?
        if let calendarId = calendarId {
            calendar = eventStore.calendar(withIdentifier: calendarId)
            logger.debug("Found calendar by ID: \(calendar?.title ?? "nil")")
        }
        if calendar == nil {
            calendar = eventStore.defaultCalendarForNewEvents
            logger.debug("Using default calendar: \(calendar?.title ?? "nil")")
        }

        guard let targetCalendar = calendar else {
            logger.error("No calendar found - both specified and default are nil")
            throw AppError.calendarNotFound
        }

        logger.info("Using calendar: \(targetCalendar.title) (ID: \(targetCalendar.calendarIdentifier))")

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = dueDate
        event.endDate = dueDate
        event.isAllDay = true
        event.notes = notes
        event.calendar = targetCalendar

        // Add an alert for the morning of the due date
        let alarm = EKAlarm(relativeOffset: -8 * 60 * 60) // 8 hours before (morning)
        event.addAlarm(alarm)

        do {
            try eventStore.save(event, span: .thisEvent)
            let eventId = event.eventIdentifier ?? "unknown"
            logger.info("Successfully created calendar event with ID: \(eventId)")
            return eventId
        } catch {
            logger.error("Failed to save calendar event: \(error.localizedDescription)")
            throw AppError.calendarEventCreationFailed(error.localizedDescription)
        }
    }

    func updateEvent(
        eventId: String,
        title: String,
        dueDate: Date,
        notes: String?
    ) async throws {
        let status = await authorizationStatus
        guard status.hasWriteAccess else {
            throw AppError.calendarPermissionDenied
        }

        guard let event = eventStore.event(withIdentifier: eventId) else {
            logger.warning("Event not found for update: \(eventId)")
            // Event might have been deleted externally - not an error
            return
        }

        event.title = title
        event.startDate = dueDate
        event.endDate = dueDate
        event.notes = notes

        do {
            try eventStore.save(event, span: .thisEvent)
            logger.info("Updated calendar event: \(eventId)")
        } catch {
            logger.error("Failed to update calendar event: \(error.localizedDescription)")
            throw AppError.calendarEventUpdateFailed(error.localizedDescription)
        }
    }

    func deleteEvent(eventId: String) async throws {
        let status = await authorizationStatus
        guard status.hasWriteAccess else {
            throw AppError.calendarPermissionDenied
        }

        guard let event = eventStore.event(withIdentifier: eventId) else {
            logger.warning("Event not found for deletion: \(eventId)")
            // Already deleted - not an error
            return
        }

        do {
            try eventStore.remove(event, span: .thisEvent)
            logger.info("Deleted calendar event: \(eventId)")
        } catch {
            logger.error("Failed to delete calendar event: \(error.localizedDescription)")
            throw AppError.calendarEventDeletionFailed(error.localizedDescription)
        }
    }

    func getAvailableCalendars() async -> [CalendarInfo] {
        let calendars = eventStore.calendars(for: .event)

        return calendars.map { calendar in
            CalendarInfo(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                isDefault: calendar == eventStore.defaultCalendarForNewEvents,
                color: calendar.cgColor.map { UIColor(cgColor: $0).hexString }
            )
        }
    }

    func getOrCreateInvoicesCalendar() async throws -> String {
        // Check if "Invoices" calendar already exists
        let calendars = eventStore.calendars(for: .event)
        if let existing = calendars.first(where: { $0.title == "Invoices" }) {
            return existing.calendarIdentifier
        }

        // Create new calendar
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = "Invoices"

        // Find a local source for the calendar
        if let localSource = eventStore.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else if let defaultSource = eventStore.defaultCalendarForNewEvents?.source {
            calendar.source = defaultSource
        } else {
            throw AppError.calendarEventCreationFailed("No calendar source available")
        }

        do {
            try eventStore.saveCalendar(calendar, commit: true)
            logger.info("Created Invoices calendar: \(calendar.calendarIdentifier)")
            return calendar.calendarIdentifier
        } catch {
            logger.error("Failed to create Invoices calendar: \(error.localizedDescription)")
            throw AppError.calendarEventCreationFailed(error.localizedDescription)
        }
    }

    func getDefaultCalendarId() async -> String? {
        eventStore.defaultCalendarForNewEvents?.calendarIdentifier
    }
}

// MARK: - UIColor Extension

private extension UIColor {
    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
