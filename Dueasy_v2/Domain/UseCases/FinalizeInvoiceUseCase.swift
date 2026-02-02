import Foundation
import os.log

/// Use case for finalizing an invoice document.
/// Validates fields, creates calendar event, and schedules notifications.
/// Also sets vendorFingerprint and documentCategory for recurring payment detection.
struct FinalizeInvoiceUseCase: Sendable {

    private let repository: DocumentRepositoryProtocol
    private let calendarService: CalendarServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let settingsManager: SettingsManager
    private let vendorFingerprintService: VendorFingerprintServiceProtocol
    private let classifierService: DocumentClassifierServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "FinalizeInvoice")

    init(
        repository: DocumentRepositoryProtocol,
        calendarService: CalendarServiceProtocol,
        notificationService: NotificationServiceProtocol,
        settingsManager: SettingsManager,
        vendorFingerprintService: VendorFingerprintServiceProtocol,
        classifierService: DocumentClassifierServiceProtocol
    ) {
        self.repository = repository
        self.calendarService = calendarService
        self.notificationService = notificationService
        self.settingsManager = settingsManager
        self.vendorFingerprintService = vendorFingerprintService
        self.classifierService = classifierService
    }

    /// Finalizes a document with validated data.
    /// - Parameters:
    ///   - document: Document to finalize
    ///   - title: Vendor/title (required)
    ///   - vendorAddress: Optional vendor address
    ///   - vendorNIP: Optional vendor NIP (tax ID)
    ///   - amount: Amount (must be > 0)
    ///   - currency: Currency code
    ///   - dueDate: Due date (required)
    ///   - documentNumber: Optional document number
    ///   - bankAccountNumber: Optional bank account for payment
    ///   - notes: Optional notes
    ///   - reminderOffsets: Days before due date to send reminders
    ///   - skipCalendar: Skip calendar event creation (e.g., if permission denied)
    @MainActor
    func execute(
        document: FinanceDocument,
        title: String,
        vendorAddress: String? = nil,
        vendorNIP: String? = nil,
        amount: Decimal,
        currency: String,
        dueDate: Date,
        documentNumber: String?,
        bankAccountNumber: String? = nil,
        notes: String?,
        reminderOffsets: [Int]?,
        skipCalendar: Bool = false
    ) async throws {
        // PRIVACY: Don't log PII or financial data
        logger.info("Finalizing document: hasTitle=\(title.count > 0), currency=\(currency) (amount/date hidden for privacy)")

        // Validate amount
        guard amount > 0 else {
            // PRIVACY: Don't log actual amount
            logger.error("Validation failed: amount must be > 0")
            throw AppError.validationAmountInvalid
        }

        // Update document fields
        document.title = title
        document.vendorAddress = vendorAddress
        document.vendorNIP = vendorNIP
        document.amount = amount
        document.currency = currency
        document.dueDate = dueDate
        document.documentNumber = documentNumber
        document.bankAccountNumber = bankAccountNumber
        document.notes = notes
        document.reminderOffsetsDays = reminderOffsets ?? settingsManager.defaultReminderOffsets
        document.notificationsEnabled = true

        // PRIVACY: Don't log NIP or address details
        logger.debug("Document fields updated - hasNIP: \(vendorNIP != nil), hasAddress: \(vendorAddress != nil)")

        // CRITICAL: Set vendor fingerprint for recurring payment detection
        // This must be done for ALL documents, not just recurring ones
        let fingerprint = vendorFingerprintService.generateFingerprint(
            vendorName: title,
            nip: vendorNIP
        )
        document.vendorFingerprint = fingerprint
        logger.info("Set vendor fingerprint: \(fingerprint.prefix(16))... for vendor (name hidden for privacy)")

        // CRITICAL: Classify document category for auto-detection filtering
        let classification = classifierService.classify(
            vendorName: title,
            ocrText: nil, // OCR text not passed through finalize - could be enhanced
            amount: amount
        )
        document.documentCategoryRaw = classification.category.rawValue
        logger.info("Classified document as category: \(classification.category.rawValue), confidence: \(String(format: "%.2f", classification.confidence))")

        // Create calendar event if not skipped
        if !skipCalendar {
            logger.info("Attempting to create calendar event (skipCalendar=false)")
            let calendarStatus = await calendarService.authorizationStatus
            logger.info("Calendar authorization status: hasWriteAccess=\(calendarStatus.hasWriteAccess)")

            if calendarStatus.hasWriteAccess {
                let eventTitle = formatEventTitle(title: title, amount: amount, currency: currency)
                let eventNotes = formatEventNotes(document: document)

                // Determine which calendar to use
                var calendarId: String? = nil
                if settingsManager.useInvoicesCalendar {
                    logger.debug("Using dedicated Invoices calendar")
                    do {
                        calendarId = try await calendarService.getOrCreateInvoicesCalendar()
                        settingsManager.invoicesCalendarId = calendarId
                        logger.info("Got/created Invoices calendar: \(calendarId ?? "nil")")
                    } catch {
                        logger.error("Failed to get/create Invoices calendar: \(error.localizedDescription)")
                        // Continue with default calendar
                    }
                }

                do {
                    // Update existing event if it exists, otherwise create new one
                    if let existingEventId = document.calendarEventId {
                        logger.debug("Attempting to update existing calendar event: \(existingEventId)")
                        do {
                            try await calendarService.updateEvent(
                                eventId: existingEventId,
                                title: eventTitle,
                                dueDate: dueDate,
                                notes: eventNotes
                            )
                            logger.info("Calendar event updated successfully: \(existingEventId)")
                        } catch {
                            logger.warning("Failed to update calendar event (may have been deleted): \(error.localizedDescription)")
                            logger.info("Creating new calendar event as fallback")
                            // Event was deleted, create a new one
                            let eventId = try await calendarService.createEvent(
                                title: eventTitle,
                                dueDate: dueDate,
                                notes: eventNotes,
                                calendarId: calendarId
                            )
                            document.calendarEventId = eventId
                            logger.info("New calendar event created with ID: \(eventId)")
                        }
                    } else {
                        logger.debug("No existing calendar event, creating new one")
                        let eventId = try await calendarService.createEvent(
                            title: eventTitle,
                            dueDate: dueDate,
                            notes: eventNotes,
                            calendarId: calendarId
                        )
                        document.calendarEventId = eventId
                        logger.info("Calendar event created with ID: \(eventId)")
                    }
                } catch {
                    logger.error("Failed to create calendar event: \(error.localizedDescription)")
                    // Don't fail the entire operation for calendar issues
                }
            } else {
                logger.warning("Calendar does not have write access - skipping event creation")
            }
        } else {
            logger.info("Calendar event creation skipped (skipCalendar=true)")
        }

        // Schedule notifications
        let notificationStatus = await notificationService.authorizationStatus
        logger.info("Notification authorization: isAuthorized=\(notificationStatus.isAuthorized), enabled=\(document.notificationsEnabled)")

        if notificationStatus.isAuthorized && document.notificationsEnabled {
            // PRIVACY: Hide vendor name if setting is enabled (default: ON)
            let notificationTitle = settingsManager.hideSensitiveDetails ? "Invoice Due" : "Invoice Due: \(title)"
            let notificationBody = formatNotificationBody(amount: amount, currency: currency)

            do {
                // Use updateReminders to handle both creation and updates (cancels old ones first)
                let scheduledIds = try await notificationService.updateReminders(
                    documentId: document.id.uuidString,
                    title: notificationTitle,
                    body: notificationBody,
                    dueDate: dueDate,
                    reminderOffsets: document.reminderOffsetsDays
                )
                logger.info("Updated \(scheduledIds.count) notification reminders (old ones cancelled)")
            } catch {
                logger.error("Failed to update notifications: \(error.localizedDescription)")
                // Don't fail for notification issues
            }
        } else {
            logger.warning("Notifications not updated - not authorized or disabled")
        }

        // Update status to scheduled
        document.status = .scheduled
        document.markUpdated()

        try await repository.update(document)
        logger.info("Document finalized and saved successfully")
    }

    // MARK: - Formatting Helpers

    private func formatEventTitle(title: String, amount: Decimal, currency: String) -> String {
        // PRIVACY: Hide sensitive details if setting is enabled (default: ON)
        if settingsManager.hideSensitiveDetails {
            return "Invoice Due"
        }

        // Show full details only if user explicitly disabled privacy protection
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let amountString = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
        return "Invoice Due: \(title) - \(amountString)"
    }

    private func formatEventNotes(document: FinanceDocument) -> String {
        var notes = "Document managed by DuEasy"

        // PRIVACY: Only include sensitive details if privacy protection is disabled
        if !settingsManager.hideSensitiveDetails {
            if let number = document.documentNumber, !number.isEmpty {
                notes += "\nInvoice No: \(number)"
            }
            if let docNotes = document.notes, !docNotes.isEmpty {
                notes += "\n\n\(docNotes)"
            }
        }

        return notes
    }

    private func formatNotificationBody(amount: Decimal, currency: String) -> String {
        // PRIVACY: Hide amount if setting is enabled (default: ON)
        if settingsManager.hideSensitiveDetails {
            return "You have an invoice payment due"
        }

        // Show amount only if user explicitly disabled privacy protection
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let amountString = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
        return "Payment of \(amountString) is due"
    }
}
