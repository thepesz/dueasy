import Foundation
import SwiftData
import os.log

/// Use case for updating an existing document.
/// Syncs changes with calendar and notifications.
/// Recalculates vendorFingerprint and documentCategory when vendor name or NIP changes.
/// Also syncs linked recurring instances when due date changes.
struct UpdateDocumentUseCase: Sendable {

    private let repository: DocumentRepositoryProtocol
    private let modelContext: ModelContext
    private let calendarService: CalendarServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let vendorFingerprintService: VendorFingerprintServiceProtocol
    private let classifierService: DocumentClassifierServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "UpdateDocument")

    init(
        repository: DocumentRepositoryProtocol,
        modelContext: ModelContext,
        calendarService: CalendarServiceProtocol,
        notificationService: NotificationServiceProtocol,
        vendorFingerprintService: VendorFingerprintServiceProtocol,
        classifierService: DocumentClassifierServiceProtocol
    ) {
        self.repository = repository
        self.modelContext = modelContext
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

        // EDGE CASE FIX: Sync linked recurring instance when due date changes
        // If this document is linked to a recurring instance, update the instance's
        // finalDueDate and its calendar event to stay synchronized
        if dueDateChanged, let instanceId = document.recurringInstanceId {
            await syncRecurringInstanceDueDate(
                instanceId: instanceId,
                newDueDate: dueDate,
                oldDueDate: oldDueDate,
                vendorName: title,
                amount: amount,
                currency: currency
            )
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

    // MARK: - Recurring Instance Sync

    /// Syncs the linked recurring instance when a document's due date changes.
    /// This prevents desynchronization between the document and its recurring instance.
    ///
    /// Updates:
    /// 1. Instance's finalDueDate to match the document
    /// 2. Instance's calendar event (if exists) to reflect new date
    @MainActor
    private func syncRecurringInstanceDueDate(
        instanceId: UUID,
        newDueDate: Date?,
        oldDueDate: Date?,
        vendorName: String,
        amount: Decimal,
        currency: String
    ) async {
        logger.info("Syncing recurring instance due date change: instance=\(instanceId)")

        // Fetch the linked instance
        let instanceDescriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> { $0.id == instanceId }
        )

        do {
            guard let instance = try modelContext.fetch(instanceDescriptor).first else {
                logger.warning("Linked recurring instance not found: \(instanceId)")
                return
            }

            // Update instance's finalDueDate
            instance.finalDueDate = newDueDate
            instance.markUpdated()

            logger.debug("Updated recurring instance finalDueDate: \(instance.periodKey)")

            // Update calendar event if exists
            if let eventId = instance.calendarEventId, let newDate = newDueDate {
                let calendarStatus = await calendarService.authorizationStatus
                if calendarStatus.hasWriteAccess {
                    do {
                        let eventTitle = formatRecurringEventTitle(
                            vendorName: vendorName,
                            amount: amount,
                            currency: currency
                        )
                        let eventNotes = "Recurring payment managed by DuEasy"

                        try await calendarService.updateEvent(
                            eventId: eventId,
                            title: eventTitle,
                            dueDate: newDate,
                            notes: eventNotes
                        )

                        logger.info("Updated recurring instance calendar event for new due date")
                    } catch {
                        logger.warning("Failed to update recurring instance calendar event: \(error.localizedDescription)")
                        // Don't fail the whole operation for calendar issues
                    }
                }
            }

            try modelContext.save()
            logger.info("Recurring instance synced with document due date change")

        } catch {
            logger.error("Failed to sync recurring instance due date: \(error.localizedDescription)")
            // Don't throw - this is a secondary operation
        }
    }

    private func formatRecurringEventTitle(vendorName: String, amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let amountString = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
        return "Recurring: \(vendorName) - \(amountString)"
    }
}
