import Foundation
import SwiftData
import os.log

/// Use case for HARD DELETING all future recurring instances for a template.
/// This is used when a user wants to stop future payments while keeping
/// the template for historical reference.
///
/// What happens:
/// 1. All future instances (expected/matched status, due date >= today) are HARD DELETED
/// 2. The template is optionally deactivated (to prevent new instances)
/// 3. Notifications for future instances are cancelled
/// 4. Calendar events for future instances are deleted from iOS Calendar
/// 5. Linked documents have their recurring linkage cleared
/// 6. Past/paid/missed instances are preserved
///
/// Use this when: user says "I don't want reminders for future payments"
/// and expects them to be completely GONE from the app and calendar.
final class DeleteFutureRecurringInstancesUseCase: @unchecked Sendable {

    private let modelContext: ModelContext
    private let templateService: RecurringTemplateServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let calendarService: CalendarServiceProtocol
    private let dateService: RecurringDateServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "DeleteFutureRecurringInstances")

    init(
        modelContext: ModelContext,
        templateService: RecurringTemplateServiceProtocol,
        notificationService: NotificationServiceProtocol,
        calendarService: CalendarServiceProtocol,
        dateService: RecurringDateServiceProtocol = RecurringDateService()
    ) {
        self.modelContext = modelContext
        self.templateService = templateService
        self.notificationService = notificationService
        self.calendarService = calendarService
        self.dateService = dateService
    }

    /// Deletes all future recurring instances for a template.
    /// - Parameters:
    ///   - templateId: The ID of the template
    ///   - deactivateTemplate: Whether to also deactivate the template (default: true)
    ///   - fromDate: Delete instances from this date onwards (default: today)
    /// - Returns: The number of instances that were cancelled
    @MainActor
    func execute(
        templateId: UUID,
        deactivateTemplate: Bool = true,
        fromDate: Date = Date()
    ) async throws -> Int {
        logger.info("Deleting future recurring instances for template: \(templateId)")

        // Fetch the template
        guard let template = try await templateService.fetchTemplate(byId: templateId) else {
            logger.error("Template not found: \(templateId)")
            throw RecurringError.templateNotFound
        }

        // Find future instances to cancel
        // Only cancel "expected" or "matched" instances with due date >= fromDate
        let descriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> {
                $0.templateId == templateId &&
                ($0.statusRaw == "expected" || $0.statusRaw == "matched") &&
                $0.expectedDueDate >= fromDate
            }
        )

        let instancesToCancel = try modelContext.fetch(descriptor)
        var cancelledCount = 0

        for instance in instancesToCancel {
            // If there's a linked document, clear its recurring linkage
            if let documentId = instance.matchedDocumentId {
                let documentDescriptor = FetchDescriptor<FinanceDocument>(
                    predicate: #Predicate<FinanceDocument> { $0.id == documentId }
                )
                if let document = try modelContext.fetch(documentDescriptor).first {
                    document.recurringInstanceId = nil
                    document.recurringTemplateId = nil
                    document.markUpdated()
                    logger.debug("Cleared recurring linkage from document: \(documentId)")
                }
            }

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

        // Optionally deactivate the template
        if deactivateTemplate {
            try await templateService.updateTemplate(template, reminderOffsets: nil, toleranceDays: nil, isActive: false)
            // PRIVACY: Don't log vendor name
            logger.info("Deactivated template: id=\(template.id)")
        }

        // Save changes
        try modelContext.save()

        // PRIVACY: Don't log vendor name
        logger.info("Deleted \(cancelledCount) future recurring instances for template: id=\(template.id)")

        return cancelledCount
    }

    /// Convenience method to delete future instances starting from a specific period.
    /// - Parameters:
    ///   - templateId: The ID of the template
    ///   - fromPeriodKey: Delete instances from this period onwards (YYYY-MM format)
    ///   - deactivateTemplate: Whether to also deactivate the template
    /// - Returns: The number of instances that were cancelled
    @MainActor
    func execute(
        templateId: UUID,
        fromPeriodKey: String,
        deactivateTemplate: Bool = true
    ) async throws -> Int {
        // Parse period key to date
        guard let fromDate = dateService.expectedDueDate(periodKey: fromPeriodKey, dayOfMonth: 1) else {
            logger.error("Invalid period key: \(fromPeriodKey)")
            throw RecurringError.schedulingFailed(reason: "Invalid period key format")
        }

        return try await execute(
            templateId: templateId,
            deactivateTemplate: deactivateTemplate,
            fromDate: fromDate
        )
    }
}
