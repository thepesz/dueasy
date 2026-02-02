import Foundation
import os.log

/// Use case for updating an existing document.
/// Syncs changes with calendar and notifications.
/// Recalculates vendorFingerprint and documentCategory when vendor name or NIP changes.
struct UpdateDocumentUseCase: Sendable {

    private let repository: DocumentRepositoryProtocol
    private let calendarService: CalendarServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let vendorFingerprintService: VendorFingerprintServiceProtocol
    private let classifierService: DocumentClassifierServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "UpdateDocument")

    init(
        repository: DocumentRepositoryProtocol,
        calendarService: CalendarServiceProtocol,
        notificationService: NotificationServiceProtocol,
        vendorFingerprintService: VendorFingerprintServiceProtocol,
        classifierService: DocumentClassifierServiceProtocol
    ) {
        self.repository = repository
        self.calendarService = calendarService
        self.notificationService = notificationService
        self.vendorFingerprintService = vendorFingerprintService
        self.classifierService = classifierService
    }

    /// Updates a document and syncs with calendar/notifications.
    /// - Parameters:
    ///   - document: Document to update
    ///   - title: New title (vendor name)
    ///   - vendorNIP: New vendor NIP (for fingerprint recalculation)
    ///   - amount: New amount
    ///   - currency: New currency
    ///   - dueDate: New due date
    ///   - documentNumber: New document number
    ///   - notes: New notes
    ///   - reminderOffsets: New reminder offsets
    @MainActor
    func execute(
        document: FinanceDocument,
        title: String,
        vendorNIP: String? = nil,
        amount: Decimal,
        currency: String,
        dueDate: Date?,
        documentNumber: String?,
        notes: String?,
        reminderOffsets: [Int]
    ) async throws {
        // Validate amount
        guard amount > 0 else {
            throw AppError.validationAmountInvalid
        }

        let oldDueDate = document.dueDate
        let dueDateChanged = oldDueDate != dueDate

        // Check if vendor name or NIP changed - need to recalculate fingerprint
        let vendorChanged = document.title != title || document.vendorNIP != vendorNIP

        // Update document fields
        document.title = title
        document.vendorNIP = vendorNIP
        document.amount = amount
        document.currency = currency
        document.dueDate = dueDate
        document.documentNumber = documentNumber
        document.notes = notes
        document.reminderOffsetsDays = reminderOffsets

        // Recalculate fingerprint if vendor changed OR fingerprint was never set
        if vendorChanged || document.vendorFingerprint == nil {
            let fingerprint = vendorFingerprintService.generateFingerprint(
                vendorName: title,
                nip: vendorNIP
            )
            document.vendorFingerprint = fingerprint
            logger.info("Updated vendor fingerprint: \(fingerprint.prefix(16))... (vendor changed: \(vendorChanged))")

            // Reclassify document category
            let classification = classifierService.classify(
                vendorName: title,
                ocrText: nil,
                amount: amount
            )
            document.documentCategoryRaw = classification.category.rawValue
            logger.info("Reclassified document as category: \(classification.category.rawValue)")
        }

        // Update calendar event if exists and due date changed
        if let eventId = document.calendarEventId, dueDateChanged, let newDueDate = dueDate {
            let calendarStatus = await calendarService.authorizationStatus
            if calendarStatus.hasWriteAccess {
                let eventTitle = formatEventTitle(title: title, amount: amount, currency: currency)
                let eventNotes = formatEventNotes(document: document)

                try await calendarService.updateEvent(
                    eventId: eventId,
                    title: eventTitle,
                    dueDate: newDueDate,
                    notes: eventNotes
                )
            }
        }

        // Update notifications if due date or offsets changed
        if document.notificationsEnabled, let newDueDate = dueDate {
            let notificationTitle = "Invoice Due: \(title)"
            let notificationBody = formatNotificationBody(amount: amount, currency: currency)

            _ = try await notificationService.updateReminders(
                documentId: document.id.uuidString,
                title: notificationTitle,
                body: notificationBody,
                dueDate: newDueDate,
                reminderOffsets: reminderOffsets
            )
        }

        document.markUpdated()
        try await repository.update(document)
    }

    // MARK: - Formatting Helpers

    private func formatEventTitle(title: String, amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let amountString = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
        return "Invoice Due: \(title) - \(amountString)"
    }

    private func formatEventNotes(document: FinanceDocument) -> String {
        var notes = "Document managed by DuEasy"
        if let number = document.documentNumber, !number.isEmpty {
            notes += "\nInvoice No: \(number)"
        }
        if let docNotes = document.notes, !docNotes.isEmpty {
            notes += "\n\n\(docNotes)"
        }
        return notes
    }

    private func formatNotificationBody(amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let amountString = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
        return "Payment of \(amountString) is due"
    }
}
