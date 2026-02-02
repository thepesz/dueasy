import Foundation
import SwiftData
import os.log

/// Use case for HARD DELETING a single recurring instance.
/// This is used when a user wants to skip a specific month's payment
/// while keeping the recurring template and other instances active.
///
/// What happens:
/// 1. The instance is HARD DELETED from the database (not soft delete)
/// 2. Any linked document has its recurring linkage cleared
/// 3. Notifications for this instance are cancelled
/// 4. Calendar event for this instance is deleted from iOS Calendar
/// 5. The template and other instances remain active
///
/// The instance is completely removed - user expects it GONE from the app.
final class DeleteRecurringInstanceUseCase: @unchecked Sendable {

    private let modelContext: ModelContext
    private let notificationService: NotificationServiceProtocol
    private let calendarService: CalendarServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "DeleteRecurringInstance")

    init(
        modelContext: ModelContext,
        notificationService: NotificationServiceProtocol,
        calendarService: CalendarServiceProtocol
    ) {
        self.modelContext = modelContext
        self.notificationService = notificationService
        self.calendarService = calendarService
    }

    /// Deletes (cancels) a single recurring instance.
    /// - Parameter instanceId: The ID of the instance to cancel
    /// - Returns: The cancelled instance
    @MainActor
    func execute(instanceId: UUID) async throws -> RecurringInstance {
        logger.info("Cancelling recurring instance: \(instanceId)")

        // Fetch the instance
        let instanceDescriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> { $0.id == instanceId }
        )
        guard let instance = try modelContext.fetch(instanceDescriptor).first else {
            logger.error("RecurringInstance not found: \(instanceId)")
            throw RecurringError.instanceNotFound
        }

        // CRITICAL FIX: If there's a linked document, clear its recurring linkage with proper error handling
        if let documentId = instance.matchedDocumentId {
            let documentDescriptor = FetchDescriptor<FinanceDocument>(
                predicate: #Predicate<FinanceDocument> { $0.id == documentId }
            )
            let documents = try modelContext.fetch(documentDescriptor)

            if documents.isEmpty {
                // Document was deleted but instance still had reference - this is acceptable
                // The instance will be deleted below, so the orphaned reference is cleaned up
                logger.warning("CLEANUP: Document \(documentId) not found - may have been deleted already. Instance reference will be removed with instance deletion.")
            } else if let document = documents.first {
                // Clear the document's recurring linkage
                logger.info("CLEANUP: Clearing recurring linkage from document \(documentId)")
                document.recurringInstanceId = nil
                document.recurringTemplateId = nil
                document.markUpdated()
                logger.debug("Cleared recurring linkage from document: \(documentId)")
            }
        } else {
            logger.debug("CLEANUP: Instance has no linked document")
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

        // Store info for logging and return before deletion
        let deletedInstance = RecurringInstance(
            id: instance.id,
            templateId: instance.templateId,
            periodKey: instance.periodKey,
            expectedDueDate: instance.expectedDueDate,
            expectedAmount: instance.expectedAmount,
            status: .cancelled
        )
        let periodKey = instance.periodKey

        // HARD DELETE the instance from database (user wants it GONE)
        modelContext.delete(instance)

        // Save changes
        try modelContext.save()

        logger.info("Successfully DELETED recurring instance: \(periodKey) from database (including calendar event)")

        return deletedInstance
    }

    /// Deletes (cancels) an instance by period key.
    /// Convenience method when you have the template ID and period key.
    /// - Parameters:
    ///   - templateId: The template ID
    ///   - periodKey: The period key (YYYY-MM format)
    /// - Returns: The cancelled instance
    @MainActor
    func execute(templateId: UUID, periodKey: String) async throws -> RecurringInstance {
        let descriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> {
                $0.templateId == templateId && $0.periodKey == periodKey
            }
        )

        guard let instance = try modelContext.fetch(descriptor).first else {
            logger.error("RecurringInstance not found for template \(templateId), period \(periodKey)")
            throw RecurringError.instanceNotFound
        }

        return try await execute(instanceId: instance.id)
    }
}
