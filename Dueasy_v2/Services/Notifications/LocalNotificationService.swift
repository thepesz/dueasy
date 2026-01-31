import Foundation
import UserNotifications
import os.log

/// Local notification service using UserNotifications framework.
/// Schedules reminders for document due dates.
final class LocalNotificationService: NotificationServiceProtocol, @unchecked Sendable {

    private let notificationCenter = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.dueasy.app", category: "Notifications")

    // MARK: - NotificationServiceProtocol

    var authorizationStatus: NotificationAuthorizationStatus {
        get async {
            let settings = await notificationCenter.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                return .notDetermined
            case .denied:
                return .denied
            case .authorized:
                return .authorized
            case .provisional:
                return .provisional
            case .ephemeral:
                return .ephemeral
            @unknown default:
                return .denied
            }
        }
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            logger.info("Notification authorization result: \(granted)")
            return granted
        } catch {
            logger.error("Notification authorization request failed: \(error.localizedDescription)")
            return false
        }
    }

    func scheduleReminders(
        documentId: String,
        title: String,
        body: String,
        dueDate: Date,
        reminderOffsets: [Int]
    ) async throws -> [String] {
        let status = await authorizationStatus
        guard status.isAuthorized else {
            throw AppError.notificationPermissionDenied
        }

        var scheduledIds: [String] = []
        let calendar = Calendar.current

        for offset in reminderOffsets {
            // Calculate reminder date
            guard let reminderDate = calendar.date(byAdding: .day, value: -offset, to: dueDate) else {
                continue
            }

            // Don't schedule reminders in the past
            if reminderDate < Date() {
                continue
            }

            // Create notification content
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = offset == 0 ? body : "\(body) - due in \(offset) day\(offset == 1 ? "" : "s")"
            content.sound = .default
            content.userInfo = [
                "documentId": documentId,
                "daysUntilDue": offset
            ]

            // Create trigger for 9 AM on the reminder date
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: reminderDate)
            dateComponents.hour = 9
            dateComponents.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

            // Create unique identifier
            let notificationId = "\(documentId)_\(offset)"

            let request = UNNotificationRequest(
                identifier: notificationId,
                content: content,
                trigger: trigger
            )

            do {
                try await notificationCenter.add(request)
                scheduledIds.append(notificationId)
                logger.info("Scheduled notification: \(notificationId) for \(dateComponents)")
            } catch {
                logger.error("Failed to schedule notification: \(error.localizedDescription)")
            }
        }

        return scheduledIds
    }

    func cancelReminders(forDocumentId documentId: String) async {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let idsToCancel = pendingRequests
            .filter { $0.identifier.hasPrefix(documentId) }
            .map { $0.identifier }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: idsToCancel)
        logger.info("Cancelled \(idsToCancel.count) notifications for document: \(documentId)")
    }

    func cancelNotifications(ids: [String]) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
        logger.info("Cancelled \(ids.count) notifications")
    }

    func getPendingNotifications(forDocumentId documentId: String) async -> [String] {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        return pendingRequests
            .filter { $0.identifier.hasPrefix(documentId) }
            .map { $0.identifier }
    }

    func updateReminders(
        documentId: String,
        title: String,
        body: String,
        dueDate: Date,
        reminderOffsets: [Int]
    ) async throws -> [String] {
        // Cancel existing reminders
        await cancelReminders(forDocumentId: documentId)

        // Schedule new reminders
        return try await scheduleReminders(
            documentId: documentId,
            title: title,
            body: body,
            dueDate: dueDate,
            reminderOffsets: reminderOffsets
        )
    }
}
