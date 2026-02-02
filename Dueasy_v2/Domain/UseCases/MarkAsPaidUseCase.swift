import Foundation
import SwiftData
import os.log

/// Use case for marking a document as paid.
/// Updates status, cancels notifications, and synchronizes linked recurring instance status.
///
/// CRITICAL FIX: Now properly updates linked RecurringInstance to .paid status,
/// ensuring calendar/notification sync and accurate statistics.
struct MarkAsPaidUseCase: Sendable {

    private let repository: DocumentRepositoryProtocol
    private let notificationService: NotificationServiceProtocol
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.dueasy.app", category: "MarkAsPaidUseCase")

    init(
        repository: DocumentRepositoryProtocol,
        notificationService: NotificationServiceProtocol,
        modelContext: ModelContext
    ) {
        self.repository = repository
        self.notificationService = notificationService
        self.modelContext = modelContext
    }

    /// Marks a document as paid.
    /// - Parameters:
    ///   - documentId: ID of the document to mark as paid
    ///   - cancelNotifications: Whether to cancel pending notifications (default: true)
    @MainActor
    func execute(
        documentId: UUID,
        cancelNotifications: Bool = true
    ) async throws {
        guard let document = try await repository.fetch(documentId: documentId) else {
            throw AppError.documentNotFound(documentId.uuidString)
        }

        // Cancel future notifications if requested
        if cancelNotifications {
            await notificationService.cancelReminders(forDocumentId: documentId.uuidString)
        }

        // Update status to paid
        document.status = .paid
        document.notificationsEnabled = false
        document.markUpdated()

        // CRITICAL FIX: Update linked recurring instance if exists
        if let instanceId = document.recurringInstanceId {
            try await syncRecurringInstancePaid(instanceId: instanceId, documentId: documentId)
        }

        try await repository.update(document)
    }

    // MARK: - Private Methods

    /// Synchronizes recurring instance status when document is marked as paid.
    /// Also updates template statistics.
    /// - Parameters:
    ///   - instanceId: ID of the recurring instance to update
    ///   - documentId: ID of the document (for logging)
    @MainActor
    private func syncRecurringInstancePaid(instanceId: UUID, documentId: UUID) async throws {
        logger.info("Syncing recurring instance \(instanceId) to paid status for document \(documentId)")

        // Fetch the linked instance
        let instanceDescriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> { $0.id == instanceId }
        )

        guard let instance = try modelContext.fetch(instanceDescriptor).first else {
            logger.warning("Recurring instance \(instanceId) not found for document \(documentId)")
            return
        }

        // Only update if not already paid
        guard instance.status != .paid else {
            logger.debug("Instance \(instanceId) already marked as paid")
            return
        }

        // Mark instance as paid
        instance.markAsPaid()
        logger.debug("Marked instance \(instanceId) as paid")

        // Cancel instance notifications if any
        if instance.notificationsScheduled {
            await notificationService.cancelNotifications(ids: instance.scheduledNotificationIds)
            instance.clearNotificationIds()
            logger.debug("Cancelled instance notifications")
        }

        // Update template statistics
        if let template = try await fetchTemplate(templateId: instance.templateId) {
            template.paidInstanceCount += 1
            template.markUpdated()
            logger.debug("Updated template \(template.id) paidInstanceCount to \(template.paidInstanceCount)")
        }

        try modelContext.save()
        logger.info("Recurring instance \(instanceId) marked as paid successfully")
    }

    /// Fetches a recurring template by ID.
    /// - Parameter templateId: ID of the template to fetch
    /// - Returns: The template if found, nil otherwise
    @MainActor
    private func fetchTemplate(templateId: UUID) async throws -> RecurringTemplate? {
        let descriptor = FetchDescriptor<RecurringTemplate>(
            predicate: #Predicate<RecurringTemplate> { $0.id == templateId }
        )
        return try modelContext.fetch(descriptor).first
    }
}
