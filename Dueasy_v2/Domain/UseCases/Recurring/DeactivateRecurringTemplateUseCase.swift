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
    private let schedulerService: RecurringSchedulerServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let calendarService: CalendarServiceProtocol
    private let settingsManager: SettingsManager
    private let logger = Logger(subsystem: "com.dueasy.app", category: "DeactivateRecurringTemplate")

    init(
        modelContext: ModelContext,
        templateService: RecurringTemplateServiceProtocol,
        schedulerService: RecurringSchedulerServiceProtocol,
        notificationService: NotificationServiceProtocol,
        calendarService: CalendarServiceProtocol,
        settingsManager: SettingsManager
    ) {
        self.modelContext = modelContext
        self.templateService = templateService
        self.schedulerService = schedulerService
        self.notificationService = notificationService
        self.calendarService = calendarService
        self.settingsManager = settingsManager
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

    /// Reactivates a previously deactivated template and regenerates future instances.
    /// When a template is reactivated:
    /// 1. Template isActive is set to true
    /// 2. New instances are generated for the next 12 months
    /// 3. Calendar events are created for new instances (if calendar sync is enabled)
    /// 4. Notifications are scheduled for new instances
    ///
    /// - Parameters:
    ///   - templateId: The ID of the template to reactivate
    ///   - reminderOffsets: Optional new reminder offsets (uses template defaults if nil)
    @MainActor
    func reactivate(templateId: UUID, reminderOffsets: [Int]? = nil) async throws {
        guard let template = try await templateService.fetchTemplate(byId: templateId) else {
            throw RecurringError.templateNotFound
        }

        guard !template.isActive else {
            logger.info("Template \(templateId) is already active")
            return
        }

        logger.info("Reactivating template: \(templateId)")

        // Reactivate template
        try await templateService.updateTemplate(template, reminderOffsets: nil, toleranceDays: nil, isActive: true)

        // Update reminder offsets if provided
        if let newOffsets = reminderOffsets {
            template.reminderOffsetsDays = newOffsets
            template.markUpdated()
            try modelContext.save()
        }

        // Regenerate instances for reactivated template
        logger.info("Regenerating instances for reactivated template...")
        let instances = try await schedulerService.generateInstances(
            for: template,
            monthsAhead: 12,  // Generate 12 months ahead
            includeHistorical: false  // Don't regenerate historical instances
        )
        logger.info("Generated \(instances.count) instances for reactivated template")

        // Create calendar events for the new instances if calendar sync is enabled
        if settingsManager.syncRecurringToiOSCalendar {
            let calendarStatus = await calendarService.authorizationStatus
            if calendarStatus.hasWriteAccess {
                var calendarEventsCreated = 0
                for instance in instances where instance.calendarEventId == nil && instance.status == .expected {
                    do {
                        let eventTitle = formatCalendarEventTitle(template: template, instance: instance)
                        let eventNotes = formatCalendarEventNotes(template: template)

                        let eventId = try await calendarService.createEvent(
                            title: eventTitle,
                            dueDate: instance.effectiveDueDate,
                            notes: eventNotes,
                            calendarId: settingsManager.invoicesCalendarId
                        )

                        instance.calendarEventId = eventId
                        calendarEventsCreated += 1
                    } catch {
                        logger.warning("Failed to create calendar event for instance \(instance.periodKey): \(error.localizedDescription)")
                    }
                }

                if calendarEventsCreated > 0 {
                    try modelContext.save()
                    logger.info("Created \(calendarEventsCreated) calendar events for reactivated template")
                }
            }
        }

        logger.info("Template reactivated successfully with \(instances.count) new instances")
    }

    // MARK: - Private Helpers

    private func formatCalendarEventTitle(template: RecurringTemplate, instance: RecurringInstance) -> String {
        let vendorName = template.vendorDisplayName
        if let amount = instance.effectiveAmount {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = template.currency
            let amountString = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
            return "Recurring: \(vendorName) - \(amountString)"
        }
        return "Recurring: \(vendorName)"
    }

    private func formatCalendarEventNotes(template: RecurringTemplate) -> String {
        "Recurring payment managed by DuEasy. Due day: \(template.dueDayOfMonth)"
    }
}
