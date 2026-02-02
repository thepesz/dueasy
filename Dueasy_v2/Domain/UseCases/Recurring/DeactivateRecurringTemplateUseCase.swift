import Foundation
import SwiftData
import os.log

/// Use case for deactivating a recurring template and DELETING all future instances.
/// This is the preferred way to "delete" a recurring payment - the template is
/// preserved for history/reactivation, but future instances are HARD DELETED.
///
/// What happens:
/// 1. Template is set to isActive = false (soft delete)
/// 2. All future instances (expected, not matched) are HARD DELETED from database
/// 3. Notifications for future instances are cancelled
/// 4. Calendar events for future instances are deleted from iOS Calendar
/// 5. Template remains in database for history/statistics/reactivation
/// 6. Matched/paid/missed instances are preserved
///
/// IMPORTANT: Templates are soft-deleted (deactivated), but instances are HARD DELETED.
/// This ensures the user sees them completely removed from their calendar and lists.
final class DeactivateRecurringTemplateUseCase: @unchecked Sendable {

    private let modelContext: ModelContext
    private let templateService: RecurringTemplateServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let calendarService: CalendarServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "DeactivateRecurringTemplate")

    init(
        modelContext: ModelContext,
        templateService: RecurringTemplateServiceProtocol,
        notificationService: NotificationServiceProtocol,
        calendarService: CalendarServiceProtocol
    ) {
        self.modelContext = modelContext
        self.templateService = templateService
        self.notificationService = notificationService
        self.calendarService = calendarService
    }

    /// Deactivates a recurring template and cancels all future instances.
    /// - Parameters:
    ///   - templateId: The ID of the template to deactivate
    ///   - cancelFutureInstancesOnly: If true, only cancel instances with status "expected" (default: true)
    /// - Returns: The number of instances that were cancelled
    @MainActor
    func execute(templateId: UUID, cancelFutureInstancesOnly: Bool = true) async throws -> Int {
        logger.info("Deactivating recurring template: \(templateId)")

        // Fetch the template
        guard let template = try await templateService.fetchTemplate(byId: templateId) else {
            logger.error("Template not found: \(templateId)")
            throw RecurringError.templateNotFound
        }

        // Deactivate the template (soft delete)
        try await templateService.updateTemplate(template, reminderOffsets: nil, toleranceDays: nil, isActive: false)

        // Find future instances to cancel
        // Only cancel "expected" instances - keep matched/paid/missed for history
        let descriptor: FetchDescriptor<RecurringInstance>
        if cancelFutureInstancesOnly {
            descriptor = FetchDescriptor<RecurringInstance>(
                predicate: #Predicate<RecurringInstance> {
                    $0.templateId == templateId && $0.statusRaw == "expected"
                }
            )
        } else {
            // Cancel all non-terminal instances (expected or matched)
            descriptor = FetchDescriptor<RecurringInstance>(
                predicate: #Predicate<RecurringInstance> {
                    $0.templateId == templateId &&
                    ($0.statusRaw == "expected" || $0.statusRaw == "matched")
                }
            )
        }

        let instancesToCancel = try modelContext.fetch(descriptor)
        var cancelledCount = 0

        for instance in instancesToCancel {
            // Cancel notifications
            if instance.notificationsScheduled {
                await notificationService.cancelNotifications(ids: instance.scheduledNotificationIds)
            }

            // Delete calendar event if exists
            if let calendarEventId = instance.calendarEventId {
                do {
                    try await calendarService.deleteEvent(eventId: calendarEventId)
                    logger.debug("Deleted calendar event for instance: \(instance.periodKey)")
                } catch {
                    // Log but don't fail - event might have been deleted externally
                    logger.warning("Failed to delete calendar event for instance \(instance.periodKey): \(error.localizedDescription)")
                }
            }

            // HARD DELETE the instance from database (user wants them GONE)
            let periodKey = instance.periodKey
            modelContext.delete(instance)
            cancelledCount += 1

            logger.debug("Deleted recurring instance: \(periodKey)")
        }

        // Save changes
        try modelContext.save()

        logger.info("Deactivated template and DELETED \(cancelledCount) future instances from database (including calendar events)")

        return cancelledCount
    }

    /// Reactivates a previously deactivated template.
    /// This is a convenience method for a future "Reactivate" feature.
    /// - Parameter templateId: The ID of the template to reactivate
    @MainActor
    func reactivate(templateId: UUID) async throws {
        guard let template = try await templateService.fetchTemplate(byId: templateId) else {
            throw RecurringError.templateNotFound
        }

        try await templateService.updateTemplate(template, reminderOffsets: nil, toleranceDays: nil, isActive: true)
        logger.info("Reactivated template: \(templateId)")
    }
}
