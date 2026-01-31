import Foundation
import os.log

/// Use case for deleting a document.
/// Removes calendar event, notifications, and stored file.
///
/// IMPORTANT: This use case extracts all needed values from the document
/// BEFORE deleting it from SwiftData to avoid accessing faulted properties
/// on a detached/deleted object (which causes a fatal crash).
struct DeleteDocumentUseCase: Sendable {

    private let repository: DocumentRepositoryProtocol
    private let fileStorageService: FileStorageServiceProtocol
    private let calendarService: CalendarServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "DeleteDocument")

    init(
        repository: DocumentRepositoryProtocol,
        fileStorageService: FileStorageServiceProtocol,
        calendarService: CalendarServiceProtocol,
        notificationService: NotificationServiceProtocol
    ) {
        self.repository = repository
        self.fileStorageService = fileStorageService
        self.calendarService = calendarService
        self.notificationService = notificationService
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

        // Also access array properties to ensure they're faulted in
        // This prevents crash when SwiftUI tries to render stale references
        _ = document.reminderOffsetsDays

        logger.debug("Extracted values - calendarEventId: \(extractedCalendarEventId ?? "nil"), fileURL: \(extractedFileURL ?? "nil")")

        // Step 1: Remove calendar event if exists
        if let eventId = extractedCalendarEventId {
            do {
                try await calendarService.deleteEvent(eventId: eventId)
                logger.info("Deleted calendar event: \(eventId)")
            } catch {
                // Log but don't fail the delete operation
                logger.warning("Failed to delete calendar event: \(error.localizedDescription)")
            }
        }

        // Step 2: Cancel notifications
        await notificationService.cancelReminders(forDocumentId: extractedDocumentIdString)
        logger.debug("Cancelled notifications for document")

        // Step 3: Delete stored file if exists
        if let fileURL = extractedFileURL {
            do {
                try await fileStorageService.deleteDocumentFile(urlString: fileURL)
                logger.info("Deleted document file: \(fileURL)")
            } catch {
                // Log but don't fail the delete operation
                logger.warning("Failed to delete document file: \(error.localizedDescription)")
            }
        }

        // Step 4: Delete the document record from SwiftData
        // This is done LAST to ensure all cleanup happens first
        try await repository.delete(documentId: documentId)
        logger.info("Document deleted successfully: \(documentId.uuidString)")
    }
}
