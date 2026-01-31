import Foundation

/// Use case for marking a document as paid.
/// Updates status and optionally cancels future notifications.
struct MarkAsPaidUseCase: Sendable {

    private let repository: DocumentRepositoryProtocol
    private let notificationService: NotificationServiceProtocol

    init(
        repository: DocumentRepositoryProtocol,
        notificationService: NotificationServiceProtocol
    ) {
        self.repository = repository
        self.notificationService = notificationService
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

        try await repository.update(document)
    }
}
