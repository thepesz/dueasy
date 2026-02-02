import Foundation
import SwiftData
import os.log

/// Use case for deleting a document.
/// Removes calendar event, notifications, stored file, and handles recurring linkage cleanup.
///
/// IMPORTANT: This use case extracts all needed values from the document
/// BEFORE deleting it from SwiftData to avoid accessing faulted properties
/// on a detached/deleted object (which causes a fatal crash).
///
/// CRITICAL FIX: Now handles recurring linkage before deletion to prevent orphaned
/// RecurringInstance.matchedDocumentId references.
struct DeleteDocumentUseCase: Sendable {

    private let repository: DocumentRepositoryProtocol
    private let fileStorageService: FileStorageServiceProtocol
    private let calendarService: CalendarServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let modelContext: ModelContext
    private let recurringSchedulerService: RecurringSchedulerServiceProtocol?
    private let recurringTemplateService: RecurringTemplateServiceProtocol?
    private let logger = Logger(subsystem: "com.dueasy.app", category: "DeleteDocument")

    init(
        repository: DocumentRepositoryProtocol,
        fileStorageService: FileStorageServiceProtocol,
        calendarService: CalendarServiceProtocol,
        notificationService: NotificationServiceProtocol,
        modelContext: ModelContext,
        recurringSchedulerService: RecurringSchedulerServiceProtocol? = nil,
        recurringTemplateService: RecurringTemplateServiceProtocol? = nil
    ) {
        self.repository = repository
        self.fileStorageService = fileStorageService
        self.calendarService = calendarService
        self.notificationService = notificationService
        self.modelContext = modelContext
        self.recurringSchedulerService = recurringSchedulerService
        self.recurringTemplateService = recurringTemplateService
    }

    /// Deletes a document and all associated resources.
    /// - Parameter documentId: ID of the document to delete
    @MainActor
    func execute(documentId: UUID) async throws {
        logger.info("Deleting document: \(documentId.uuidString)")

        guard let document = try await repository.fetch(documentId: documentId) else {
            logger.error("Document not found: \(documentId.uuidString)")
            throw AppError.documentNotFound(documentId.uuidString)
        }

        // CRITICAL: Extract ALL needed values BEFORE any deletion
        // SwiftData lazy-loads properties, and accessing them after deletion
        // causes a fatal "detached from context" crash
        let extractedCalendarEventId = document.calendarEventId
        let extractedFileURL = document.sourceFileURL
        let extractedDocumentIdString = documentId.uuidString
        let extractedRecurringInstanceId = document.recurringInstanceId
        let extractedRecurringTemplateId = document.recurringTemplateId

        // Also access array properties to ensure they're faulted in
        // This prevents crash when SwiftUI tries to render stale references
        _ = document.reminderOffsetsDays

        logger.debug("Extracted values - calendarEventId: \(extractedCalendarEventId ?? "nil"), fileURL: \(extractedFileURL ?? "nil"), recurringInstanceId: \(extractedRecurringInstanceId?.uuidString ?? "nil")")

        // Step 1: CRITICAL FIX - Handle recurring linkage if exists
        // This prevents orphaned RecurringInstance.matchedDocumentId references
        if let instanceId = extractedRecurringInstanceId {
            logger.info("Document is linked to recurring instance \(instanceId), unlinking before deletion...")
            try await unlinkFromRecurringInstance(
                instanceId: instanceId,
                templateId: extractedRecurringTemplateId,
                document: document
            )
        }

        // Step 2: Remove calendar event if exists
        if let eventId = extractedCalendarEventId {
            do {
                try await calendarService.deleteEvent(eventId: eventId)
                logger.info("Deleted calendar event: \(eventId)")
            } catch {
                // Log but don't fail the delete operation
                logger.warning("Failed to delete calendar event: \(error.localizedDescription)")
            }
        }

        // Step 3: Cancel notifications
        await notificationService.cancelReminders(forDocumentId: extractedDocumentIdString)
        logger.debug("Cancelled notifications for document")

        // Step 4: Delete stored file if exists
        if let fileURL = extractedFileURL {
            do {
                try await fileStorageService.deleteDocumentFile(urlString: fileURL)
                logger.info("Deleted document file: \(fileURL)")
            } catch {
                // Log but don't fail the delete operation
                logger.warning("Failed to delete document file: \(error.localizedDescription)")
            }
        }

        // Step 5: Delete the document record from SwiftData
        // This is done LAST to ensure all cleanup happens first
        try await repository.delete(documentId: documentId)
        logger.info("Document deleted successfully: \(documentId.uuidString)")
    }

    // MARK: - Private Helpers

    /// Unlinks a document from its recurring instance before deletion.
    /// Reverts the instance to "expected" status and reschedules notifications.
    @MainActor
    private func unlinkFromRecurringInstance(
        instanceId: UUID,
        templateId: UUID?,
        document: FinanceDocument
    ) async throws {
        // Fetch the recurring instance
        let instanceDescriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> { $0.id == instanceId }
        )
        guard let instance = try modelContext.fetch(instanceDescriptor).first else {
            logger.warning("RecurringInstance \(instanceId) not found - may have been deleted already")
            // Clear document's recurring linkage anyway
            document.recurringInstanceId = nil
            document.recurringTemplateId = nil
            document.markUpdated()
            return
        }

        // Cancel existing notifications for this instance
        if instance.notificationsScheduled {
            await notificationService.cancelNotifications(ids: instance.scheduledNotificationIds)
            instance.clearNotificationIds()
            logger.debug("Cancelled instance notifications")
        }

        // Unlink the instance (reverts to expected status)
        instance.unlinkDocument()
        logger.info("Unlinked document from instance \(instanceId), status reverted to expected")

        // Clear document linkage
        document.recurringInstanceId = nil
        document.recurringTemplateId = nil
        document.markUpdated()

        // Save changes
        try modelContext.save()

        // Reschedule notifications for the now-expected instance (if template is active)
        if let templateId = templateId,
           let templateService = recurringTemplateService,
           let schedulerService = recurringSchedulerService {
            do {
                let template = try await templateService.fetchTemplate(byId: templateId)
                if let template = template, template.isActive {
                    try await schedulerService.scheduleNotifications(
                        for: instance,
                        template: template,
                        vendorName: template.vendorDisplayName
                    )
                    logger.info("Rescheduled notifications for instance after document unlink")
                }
            } catch {
                // Log but don't fail - notifications are not critical
                logger.warning("Failed to reschedule notifications after unlink: \(error.localizedDescription)")
            }
        }
    }
}
