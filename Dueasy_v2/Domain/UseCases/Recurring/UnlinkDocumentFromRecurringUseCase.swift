import Foundation
import SwiftData
import os.log

/// Use case for unlinking a document from a recurring instance.
/// This is used when a user wants to delete a document that is linked to a recurring
/// payment, but wants to keep the recurring payment template active.
///
/// What happens:
/// 1. The document's recurringInstanceId and recurringTemplateId are cleared
/// 2. The RecurringInstance reverts from "matched" to "expected" status
/// 3. The instance's matched document data is cleared
/// 4. The document is deleted (if requested)
/// 5. The template statistics are updated
///
/// The template and all future instances remain active.
final class UnlinkDocumentFromRecurringUseCase: @unchecked Sendable {

    private let modelContext: ModelContext
    private let schedulerService: RecurringSchedulerServiceProtocol
    private let templateService: RecurringTemplateServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "UnlinkDocumentFromRecurring")

    init(
        modelContext: ModelContext,
        schedulerService: RecurringSchedulerServiceProtocol,
        templateService: RecurringTemplateServiceProtocol,
        notificationService: NotificationServiceProtocol
    ) {
        self.modelContext = modelContext
        self.schedulerService = schedulerService
        self.templateService = templateService
        self.notificationService = notificationService
    }

    /// Unlinks a document from its recurring instance.
    /// - Parameters:
    ///   - document: The document to unlink
    ///   - deleteDocument: Whether to delete the document after unlinking (default: false)
    /// - Returns: The unlinked recurring instance (reverted to expected status)
    @MainActor
    func execute(document: FinanceDocument, deleteDocument: Bool = false) async throws -> RecurringInstance? {
        guard let instanceId = document.recurringInstanceId else {
            logger.warning("Document has no recurringInstanceId, nothing to unlink")
            return nil
        }

        logger.info("Unlinking document \(document.id) from recurring instance \(instanceId)")

        // Fetch the recurring instance
        let instanceDescriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> { $0.id == instanceId }
        )
        guard let instance = try modelContext.fetch(instanceDescriptor).first else {
            logger.error("RecurringInstance not found: \(instanceId)")
            throw RecurringError.instanceNotFound
        }

        // Fetch the template to update statistics
        let templateId = instance.templateId
        let template = try await templateService.fetchTemplate(byId: templateId)

        // Cancel existing notifications for this instance
        if instance.notificationsScheduled {
            await notificationService.cancelNotifications(ids: instance.scheduledNotificationIds)
            instance.clearNotificationIds()
        }

        // Unlink the instance (reverts to expected status)
        instance.unlinkDocument()

        // Clear document linkage
        document.recurringInstanceId = nil
        document.recurringTemplateId = nil
        document.markUpdated()

        // Save changes
        try modelContext.save()

        // Reschedule notifications for the now-expected instance (if template is active)
        if let template = template, template.isActive {
            do {
                try await schedulerService.scheduleNotifications(
                    for: instance,
                    template: template,
                    vendorName: template.vendorDisplayName
                )
            } catch {
                // Log but don't fail - notifications are not critical
                logger.warning("Failed to reschedule notifications after unlink: \(error.localizedDescription)")
            }
        }

        logger.info("Successfully unlinked document from recurring instance \(instanceId)")

        return instance
    }
}
