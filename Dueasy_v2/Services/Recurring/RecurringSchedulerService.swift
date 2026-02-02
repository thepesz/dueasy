import Foundation
import SwiftData
import os.log

/// Service for generating recurring instances and scheduling their notifications.
/// Generates instances ahead of time (default: 3 months) and manages notification lifecycle.
/// Optionally syncs to iOS Calendar based on user settings.
protocol RecurringSchedulerServiceProtocol: Sendable {
    /// Generates future instances for a template.
    /// - Parameters:
    ///   - template: The recurring template
    ///   - monthsAhead: Number of months to generate ahead (default: 3)
    /// - Returns: Array of generated instances
    func generateInstances(
        for template: RecurringTemplate,
        monthsAhead: Int
    ) async throws -> [RecurringInstance]

    /// Schedules notifications for an instance.
    /// - Parameters:
    ///   - instance: The recurring instance
    ///   - template: The parent template (for reminder offsets)
    ///   - vendorName: Vendor name for notification content
    func scheduleNotifications(
        for instance: RecurringInstance,
        template: RecurringTemplate,
        vendorName: String
    ) async throws

    /// Updates notifications after an instance is matched with a document.
    /// - Parameters:
    ///   - instance: The matched instance
    ///   - template: The parent template
    ///   - vendorName: Vendor name for notification content
    func updateNotificationsAfterMatch(
        for instance: RecurringInstance,
        template: RecurringTemplate,
        vendorName: String
    ) async throws

    /// Cancels notifications for an instance.
    /// - Parameter instance: The instance to cancel notifications for
    func cancelNotifications(for instance: RecurringInstance) async throws

    /// Fetches all instances for a template.
    /// - Parameter templateId: The template ID
    /// - Returns: Array of instances sorted by expected due date
    func fetchInstances(forTemplateId templateId: UUID) async throws -> [RecurringInstance]

    /// Fetches upcoming instances across all templates.
    /// - Parameter limit: Maximum number of instances to return
    /// - Returns: Array of upcoming instances
    func fetchUpcomingInstances(limit: Int) async throws -> [RecurringInstance]

    /// Fetches an instance by period key.
    /// - Parameters:
    ///   - templateId: The template ID
    ///   - periodKey: The period key (YYYY-MM)
    /// - Returns: The instance if found
    func fetchInstance(templateId: UUID, periodKey: String) async throws -> RecurringInstance?

    /// Marks an instance as paid.
    /// - Parameter instance: The instance to mark as paid
    func markInstanceAsPaid(_ instance: RecurringInstance) async throws

    /// Marks overdue expected instances as missed.
    /// Should be called periodically (e.g., on app launch).
    func markOverdueInstancesAsMissed() async throws -> Int

    /// Creates a historical instance for a specific period (for linking existing documents).
    /// - Parameters:
    ///   - template: The recurring template
    ///   - periodKey: The period key (YYYY-MM)
    ///   - expectedDueDate: The expected due date for this instance
    /// - Returns: The created instance
    func createHistoricalInstance(
        for template: RecurringTemplate,
        periodKey: String,
        expectedDueDate: Date
    ) async throws -> RecurringInstance
}

/// Default implementation of RecurringSchedulerService
@MainActor
final class RecurringSchedulerService: RecurringSchedulerServiceProtocol {

    private let modelContext: ModelContext
    private let notificationService: NotificationServiceProtocol
    private let calendarService: CalendarServiceProtocol
    private let settingsManager: SettingsManager
    private let logger = Logger(subsystem: "com.dueasy.app", category: "RecurringScheduler")

    /// Default number of months to generate instances ahead
    static let defaultMonthsAhead = 3

    init(
        modelContext: ModelContext,
        notificationService: NotificationServiceProtocol,
        calendarService: CalendarServiceProtocol,
        settingsManager: SettingsManager
    ) {
        self.modelContext = modelContext
        self.notificationService = notificationService
        self.calendarService = calendarService
        self.settingsManager = settingsManager
    }

    // MARK: - Instance Generation

    func generateInstances(
        for template: RecurringTemplate,
        monthsAhead: Int = defaultMonthsAhead
    ) async throws -> [RecurringInstance] {
        let calendar = Calendar.current
        let today = Date()

        var generatedInstances: [RecurringInstance] = []

        // Generate for current month and next N months
        for monthOffset in 0...monthsAhead {
            guard let targetMonth = calendar.date(byAdding: .month, value: monthOffset, to: today) else {
                continue
            }

            let periodKey = RecurringInstance.periodKey(for: targetMonth)

            // Check if instance already exists for this period
            if let existingInstance = try await fetchInstance(templateId: template.id, periodKey: periodKey) {
                generatedInstances.append(existingInstance)
                continue
            }

            // Calculate expected due date
            guard let expectedDueDate = RecurringInstance.expectedDueDate(
                periodKey: periodKey,
                dayOfMonth: template.dueDayOfMonth
            ) else {
                continue
            }

            // Don't create instances for past dates (unless it's the current month)
            if expectedDueDate < today && monthOffset > 0 {
                continue
            }

            // Create new instance
            let instance = RecurringInstance(
                templateId: template.id,
                periodKey: periodKey,
                expectedDueDate: expectedDueDate,
                expectedAmount: template.amountMin // Use min amount as expected
            )

            modelContext.insert(instance)
            generatedInstances.append(instance)

            logger.info("Generated recurring instance for \(template.vendorDisplayName): \(periodKey)")
        }

        try modelContext.save()
        logger.info("📅 Saved \(generatedInstances.count) recurring instances to SwiftData")

        // Schedule notifications and optionally sync to iOS Calendar for future instances
        for instance in generatedInstances where instance.status == .expected && instance.expectedDueDate >= today {
            try await scheduleNotifications(
                for: instance,
                template: template,
                vendorName: template.vendorDisplayName
            )
        }

        return generatedInstances
    }

    // MARK: - Notification Management

    func scheduleNotifications(
        for instance: RecurringInstance,
        template: RecurringTemplate,
        vendorName: String
    ) async throws {
        // Cancel any existing notifications first
        if instance.notificationsScheduled {
            await notificationService.cancelNotifications(ids: instance.scheduledNotificationIds)
        }

        let documentId = "recurring_\(instance.id.uuidString)"
        let title = vendorName
        let body = L10n.Recurring.toggleDescription.localized

        let notificationIds = try await notificationService.scheduleReminders(
            documentId: documentId,
            title: title,
            body: body,
            dueDate: instance.effectiveDueDate,
            reminderOffsets: template.reminderOffsetsDays
        )

        instance.updateNotificationIds(notificationIds)

        // Sync to iOS Calendar if setting is enabled
        if settingsManager.syncRecurringToiOSCalendar {
            await syncToiOSCalendar(
                instance: instance,
                vendorName: vendorName,
                template: template
            )
        }

        try modelContext.save()

        logger.info("Scheduled \(notificationIds.count) notifications for recurring instance: \(instance.periodKey)")
    }

    func updateNotificationsAfterMatch(
        for instance: RecurringInstance,
        template: RecurringTemplate,
        vendorName: String
    ) async throws {
        // Cancel existing notifications
        await notificationService.cancelNotifications(ids: instance.scheduledNotificationIds)
        instance.clearNotificationIds()

        // Reschedule with the final due date
        if instance.status == .matched {
            let documentId = "recurring_\(instance.id.uuidString)"
            let title = vendorName
            let body = instance.invoiceNumber.map { "Invoice \($0)" } ?? L10n.Recurring.toggleDescription.localized

            let notificationIds = try await notificationService.scheduleReminders(
                documentId: documentId,
                title: title,
                body: body,
                dueDate: instance.effectiveDueDate,
                reminderOffsets: template.reminderOffsetsDays
            )

            instance.updateNotificationIds(notificationIds)

            // Update iOS Calendar event if sync is enabled
            if settingsManager.syncRecurringToiOSCalendar {
                await syncToiOSCalendar(
                    instance: instance,
                    vendorName: vendorName,
                    template: template
                )
            }

            try modelContext.save()

            logger.info("Updated notifications for matched instance: \(instance.periodKey)")
        }
    }

    func cancelNotifications(for instance: RecurringInstance) async throws {
        await notificationService.cancelNotifications(ids: instance.scheduledNotificationIds)
        instance.clearNotificationIds()

        // Remove from iOS Calendar if there's a calendar event
        if let calendarEventId = instance.calendarEventId {
            do {
                try await calendarService.deleteEvent(eventId: calendarEventId)
                instance.clearCalendarEventId()
                logger.info("Deleted calendar event for recurring instance: \(instance.periodKey)")
            } catch {
                // Log but don't fail - event might have been deleted externally
                logger.warning("Failed to delete calendar event: \(error.localizedDescription)")
                instance.clearCalendarEventId()
            }
        }

        try modelContext.save()
    }

    // MARK: - iOS Calendar Sync

    /// Syncs a recurring instance to iOS Calendar.
    /// Only called when syncRecurringToiOSCalendar setting is enabled.
    private func syncToiOSCalendar(
        instance: RecurringInstance,
        vendorName: String,
        template: RecurringTemplate
    ) async {
        // Check calendar authorization
        let calendarStatus = await calendarService.authorizationStatus
        guard calendarStatus.hasWriteAccess else {
            logger.warning("Cannot sync recurring to iOS Calendar - no write access")
            return
        }

        // Format event title based on privacy settings
        let eventTitle: String
        if settingsManager.hideSensitiveDetails {
            eventTitle = "Expected Payment"
        } else {
            if let amount = instance.effectiveAmount {
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.currencyCode = template.currency
                let amountString = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
                eventTitle = "\(vendorName) - \(amountString)"
            } else {
                eventTitle = "\(vendorName) - Expected"
            }
        }

        let eventNotes = "Recurring payment managed by DuEasy\nStatus: \(instance.status.displayName)"

        do {
            // Determine which calendar to use
            var calendarId: String? = nil
            if settingsManager.useInvoicesCalendar {
                calendarId = try await calendarService.getOrCreateInvoicesCalendar()
            }

            // If instance already has a calendar event, update it instead of creating new
            if let existingEventId = instance.calendarEventId {
                try await calendarService.updateEvent(
                    eventId: existingEventId,
                    title: eventTitle,
                    dueDate: instance.effectiveDueDate,
                    notes: eventNotes
                )
                logger.info("Updated calendar event for recurring instance: \(instance.periodKey)")
            } else {
                // Create new calendar event and store the ID
                let eventId = try await calendarService.createEvent(
                    title: eventTitle,
                    dueDate: instance.effectiveDueDate,
                    notes: eventNotes,
                    calendarId: calendarId
                )
                instance.updateCalendarEventId(eventId)
                logger.info("Created calendar event for recurring instance: \(instance.periodKey), eventId: \(eventId)")
            }
        } catch {
            logger.error("Failed to sync recurring instance to iOS Calendar: \(error.localizedDescription)")
            // Don't fail the operation for calendar sync issues
        }
    }

    // MARK: - Instance Queries

    func fetchInstances(forTemplateId templateId: UUID) async throws -> [RecurringInstance] {
        let descriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> { $0.templateId == templateId },
            sortBy: [SortDescriptor(\.expectedDueDate)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchUpcomingInstances(limit: Int) async throws -> [RecurringInstance] {
        let today = Date()
        let descriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> {
                ($0.statusRaw == "expected" || $0.statusRaw == "matched") && $0.expectedDueDate >= today
            },
            sortBy: [SortDescriptor(\.expectedDueDate)]
        )
        var limitedDescriptor = descriptor
        limitedDescriptor.fetchLimit = limit
        return try modelContext.fetch(limitedDescriptor)
    }

    func fetchInstance(templateId: UUID, periodKey: String) async throws -> RecurringInstance? {
        let descriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> {
                $0.templateId == templateId && $0.periodKey == periodKey
            }
        )
        let instances = try modelContext.fetch(descriptor)
        return instances.first
    }

    // MARK: - Status Updates

    func markInstanceAsPaid(_ instance: RecurringInstance) async throws {
        instance.markAsPaid()

        // Cancel notifications
        await notificationService.cancelNotifications(ids: instance.scheduledNotificationIds)
        instance.clearNotificationIds()

        try modelContext.save()

        logger.info("Marked recurring instance as paid: \(instance.periodKey)")
    }

    func markOverdueInstancesAsMissed() async throws -> Int {
        let today = Date()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        // Find expected instances with due dates in the past
        let descriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> {
                $0.statusRaw == "expected" && $0.expectedDueDate < yesterday
            }
        )

        let overdueInstances = try modelContext.fetch(descriptor)

        for instance in overdueInstances {
            instance.markAsMissed()

            // Cancel any remaining notifications
            await notificationService.cancelNotifications(ids: instance.scheduledNotificationIds)
            instance.clearNotificationIds()
        }

        if !overdueInstances.isEmpty {
            try modelContext.save()
            logger.info("Marked \(overdueInstances.count) overdue instances as missed")
        }

        return overdueInstances.count
    }

    // MARK: - Historical Instance Creation

    func createHistoricalInstance(
        for template: RecurringTemplate,
        periodKey: String,
        expectedDueDate: Date
    ) async throws -> RecurringInstance {
        logger.info("Creating historical instance for \(template.vendorDisplayName): \(periodKey)")

        // Check if instance already exists
        if let existing = try await fetchInstance(templateId: template.id, periodKey: periodKey) {
            logger.info("Historical instance already exists: \(existing.id)")
            return existing
        }

        // Create new historical instance
        let instance = RecurringInstance(
            templateId: template.id,
            periodKey: periodKey,
            expectedDueDate: expectedDueDate,
            expectedAmount: template.amountMin
        )

        modelContext.insert(instance)
        try modelContext.save()

        logger.info("Created historical instance: \(instance.id) for period \(periodKey)")

        return instance
    }
}
