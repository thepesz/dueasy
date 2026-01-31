import Foundation
import UIKit
import Observation
import os.log

/// ViewModel for the document review screen.
/// Handles OCR processing, field editing, and document finalization.
@MainActor
@Observable
final class DocumentReviewViewModel {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "DocumentReview")

    // MARK: - State

    var images: [UIImage] = []
    var isProcessingOCR: Bool = false
    var hasProcessedOCR: Bool = false  // Guard against multiple OCR runs
    var isSaving: Bool = false

    // Editable fields
    var vendorName: String = ""
    var vendorAddress: String = ""
    var amount: String = ""
    var currency: String = "PLN"
    var dueDate: Date = Date()
    var hasDueDate: Bool = true
    var documentNumber: String = ""
    var bankAccountNumber: String = ""
    var notes: String = ""

    // Amount selection - all detected amounts for dropdown
    var suggestedAmounts: [(value: Decimal, context: String)] = []
    var selectedAmountIndex: Int = 0

    // Reminder settings
    var reminderOffsets: Set<Int> = [7, 1, 0]

    // Calendar settings
    var addToCalendar: Bool = true

    // Analysis result
    var analysisResult: DocumentAnalysisResult?
    var ocrConfidence: Double = 0.0
    var ocrText: String = "" // Store OCR text for keyword learning

    // Validation and errors
    var error: AppError?
    var showDueDateWarning: Bool = false
    var validationErrors: [String] = []

    // Permission state
    var calendarPermissionGranted: Bool = false
    var notificationPermissionGranted: Bool = false
    var isRequestingPermissions: Bool = false

    // MARK: - Dependencies

    private let document: FinanceDocument
    private let extractUseCase: ExtractAndSuggestFieldsUseCase
    private let finalizeUseCase: FinalizeInvoiceUseCase
    private let checkPermissionsUseCase: CheckPermissionsUseCase
    private let settingsManager: SettingsManager
    private let keywordLearningService: KeywordLearningService?
    private let learningDataService: LearningDataService?

    var documentId: UUID { document.id }

    // MARK: - Computed Properties

    var amountDecimal: Decimal? {
        // Parse amount string to decimal
        var normalized = amount
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")

        // Handle comma as decimal separator
        if normalized.contains(",") && !normalized.contains(".") {
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        } else if normalized.contains(",") && normalized.contains(".") {
            // European format: remove thousand separators (dots)
            if let commaIndex = normalized.lastIndex(of: ","),
               let dotIndex = normalized.lastIndex(of: "."),
               commaIndex > dotIndex {
                normalized = normalized.replacingOccurrences(of: ".", with: "")
                normalized = normalized.replacingOccurrences(of: ",", with: ".")
            } else {
                // US format
                normalized = normalized.replacingOccurrences(of: ",", with: "")
            }
        }

        return Decimal(string: normalized)
    }

    var isValid: Bool {
        validate().isEmpty
    }

    var hasLowConfidence: Bool {
        ocrConfidence < 0.5
    }

    var canSave: Bool {
        isValid && !isSaving && !isProcessingOCR
    }

    // MARK: - Initialization

    init(
        document: FinanceDocument,
        images: [UIImage],
        extractUseCase: ExtractAndSuggestFieldsUseCase,
        finalizeUseCase: FinalizeInvoiceUseCase,
        checkPermissionsUseCase: CheckPermissionsUseCase,
        settingsManager: SettingsManager,
        keywordLearningService: KeywordLearningService? = nil,
        learningDataService: LearningDataService? = nil
    ) {
        self.document = document
        self.images = images
        self.extractUseCase = extractUseCase
        self.finalizeUseCase = finalizeUseCase
        self.checkPermissionsUseCase = checkPermissionsUseCase
        self.settingsManager = settingsManager
        self.keywordLearningService = keywordLearningService
        self.learningDataService = learningDataService

        // Initialize reminder offsets and calendar settings from settings
        self.reminderOffsets = Set(settingsManager.defaultReminderOffsets)
        self.currency = settingsManager.defaultCurrency
        self.addToCalendar = settingsManager.addToCalendarByDefault
    }

    // MARK: - Actions

    func processImages() async {
        // CRITICAL: Guard against multiple OCR runs
        guard !hasProcessedOCR && !isProcessingOCR else {
            logger.warning("Skipping duplicate OCR processing - already processed or in progress")
            return
        }

        logger.info("Processing \(self.images.count) images for document \(self.document.id)")
        isProcessingOCR = true
        hasProcessedOCR = true  // Mark as processed immediately to prevent re-runs
        error = nil

        do {
            let result = try await extractUseCase.execute(
                images: images,
                documentType: document.type
            )

            analysisResult = result
            ocrConfidence = result.overallConfidence
            ocrText = result.rawOCRText ?? "" // Store for keyword learning

            // PRIVACY: Only log metrics, not actual data (PII + financial)
            logger.info("OCR/Parsing result: hasVendor=\(result.vendorName != nil), hasAmount=\(result.amount != nil), hasDueDate=\(result.dueDate != nil), confidence=\(result.overallConfidence)")

            // Populate fields from analysis result
            if let vendor = result.vendorName, !vendor.isEmpty {
                vendorName = vendor
                logger.debug("Set vendor: \(vendor)")
            }
            if let address = result.vendorAddress, !address.isEmpty {
                vendorAddress = address
                logger.debug("Set vendorAddress: \(address)")
            }

            // Store all suggested amounts for dropdown
            self.suggestedAmounts = result.suggestedAmounts.map { ($0.0, $0.1) }
            self.selectedAmountIndex = 0
            logger.info("Found \(self.suggestedAmounts.count) suggested amounts")

            if let extractedAmount = result.amount {
                amount = formatAmount(extractedAmount)
                logger.debug("Set amount: \(self.amount)")
            }
            if let extractedCurrency = result.currency {
                currency = extractedCurrency
                logger.debug("Set currency: \(extractedCurrency)")
            }
            if let extractedDate = result.dueDate {
                dueDate = extractedDate
                hasDueDate = true
                checkDueDateWarning()
                logger.debug("Set dueDate: \(extractedDate)")
            }
            if let number = result.documentNumber, !number.isEmpty {
                documentNumber = number
                logger.debug("Set documentNumber: \(number)")
            }
            if let bankAccount = result.bankAccountNumber, !bankAccount.isEmpty {
                bankAccountNumber = bankAccount
                logger.debug("Set bankAccountNumber: \(bankAccount)")
            }

        } catch let appError as AppError {
            logger.error("OCR failed with AppError: \(appError.localizedDescription)")
            error = appError
            // Still allow manual entry even if OCR fails
        } catch {
            logger.error("OCR failed with error: \(error.localizedDescription)")
            self.error = .ocrFailed(error.localizedDescription)
        }

        isProcessingOCR = false
    }

    func save() async -> Bool {
        // PRIVACY: Don't log sensitive data (PII + financial)
        logger.info("Saving document - hasVendor: \(self.vendorName.count > 0), hasAmount: \(self.amountDecimal != nil), hasDueDate: \(self.hasDueDate)")

        validationErrors = validate()
        guard validationErrors.isEmpty else {
            logger.warning("Validation failed: \(self.validationErrors)")
            return false
        }

        isSaving = true
        error = nil

        let finalAmount = amountDecimal ?? 0
        // Due date is REQUIRED for invoices - validation ensures hasDueDate is true
        let finalDueDate = dueDate

        // PRIVACY: Don't log financial data
        logger.info("Calling finalizeUseCase (amount and date hidden for privacy)")

        // ADAPTIVE LEARNING: Record corrections before saving
        recordCorrections()

        do {
            try await finalizeUseCase.execute(
                document: document,
                title: vendorName,
                vendorAddress: vendorAddress.isEmpty ? nil : vendorAddress,
                amount: finalAmount,
                currency: currency,
                dueDate: finalDueDate,
                documentNumber: documentNumber.isEmpty ? nil : documentNumber,
                bankAccountNumber: bankAccountNumber.isEmpty ? nil : bankAccountNumber,
                notes: notes.isEmpty ? nil : notes,
                reminderOffsets: Array(reminderOffsets).sorted(by: >),
                skipCalendar: !addToCalendar
            )

            logger.info("Document saved successfully")
            isSaving = false
            return true
        } catch let appError as AppError {
            logger.error("Save failed with AppError: \(appError.localizedDescription)")
            error = appError
            isSaving = false
            return false
        } catch {
            logger.error("Save failed with error: \(error.localizedDescription)")
            self.error = .unknown(error.localizedDescription)
            isSaving = false
            return false
        }
    }

    func toggleReminderOffset(_ offset: Int) {
        if reminderOffsets.contains(offset) {
            reminderOffsets.remove(offset)
        } else {
            reminderOffsets.insert(offset)
        }
    }

    func selectAmount(at index: Int) {
        guard index >= 0 && index < self.suggestedAmounts.count else { return }
        self.selectedAmountIndex = index
        self.amount = formatAmount(self.suggestedAmounts[index].value)
        let selectedValue = self.suggestedAmounts[index].value
        let selectedContext = self.suggestedAmounts[index].context
        // PRIVACY: Don't log actual amount or context (may contain invoice text)
        logger.info("Selected amount candidate #\(index) (value hidden for privacy)")
    }

    func clearError() {
        error = nil
    }

    // MARK: - Validation

    func validate() -> [String] {
        var errors: [String] = []

        if vendorName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Vendor name is required")
        }

        if amountDecimal == nil || amountDecimal! <= 0 {
            errors.append("Amount must be greater than zero")
        }

        // CRITICAL: Due date is REQUIRED for invoices
        // An invoice without a due date doesn't make sense for DueEasy
        if !hasDueDate {
            errors.append("Due date is required for invoices")
        }

        return errors
    }

    func checkDueDateWarning() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let selectedDate = calendar.startOfDay(for: dueDate)

        showDueDateWarning = selectedDate < today
    }

    // MARK: - Adaptive Learning

    /// Record corrections from user edits to improve future parsing
    private func recordCorrections() {
        guard let learningService = keywordLearningService,
              let result = analysisResult,
              !ocrText.isEmpty else {
            return
        }

        logger.info("Recording corrections for adaptive learning")

        // Check if amount was corrected
        if let autoAmount = result.amount,
           let manualAmount = amountDecimal,
           autoAmount != manualAmount {
            logger.info("Amount was corrected: \(autoAmount) -> \(manualAmount)")
            learningService.learnFromCorrection(
                correctedValue: amount,
                ocrText: ocrText,
                fieldType: .amount
            )
        } else if result.amount == nil && self.amountDecimal != nil {
            // Amount was added manually (OCR missed it)
            // PRIVACY: Don't log actual amount (financial data)
            logger.info("Amount was added manually (value hidden for privacy)")
            learningService.learnFromCorrection(
                correctedValue: amount,
                ocrText: ocrText,
                fieldType: .amount
            )
        }

        // Check if vendor was corrected
        let autoVendor = result.vendorName ?? ""
        let manualVendor = vendorName.trimmingCharacters(in: .whitespaces)
        if autoVendor != manualVendor && !manualVendor.isEmpty {
            logger.info("Vendor was corrected: '\(autoVendor)' -> '\(manualVendor)'")
            learningService.learnFromCorrection(
                correctedValue: manualVendor,
                ocrText: ocrText,
                fieldType: .vendor
            )
        }

        // Check if invoice number was corrected
        let autoNumber = result.documentNumber ?? ""
        let manualNumber = documentNumber.trimmingCharacters(in: .whitespaces)
        if autoNumber != manualNumber && !manualNumber.isEmpty {
            logger.info("Invoice number was corrected: '\(autoNumber)' -> '\(manualNumber)'")
            learningService.learnFromCorrection(
                correctedValue: manualNumber,
                ocrText: ocrText,
                fieldType: .invoiceNumber
            )
        }

        // Check if due date was corrected
        if let autoDueDate = result.dueDate {
            let calendar = Calendar.current
            if !calendar.isDate(autoDueDate, inSameDayAs: self.dueDate) {
                logger.info("Due date was corrected: \(autoDueDate) -> \(self.dueDate)")
                // Learn from the date string in context
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "dd.MM.yyyy"
                let dateString = dateFormatter.string(from: self.dueDate)
                learningService.learnFromCorrection(
                    correctedValue: dateString,
                    ocrText: ocrText,
                    fieldType: .dueDate
                )
            }
        }

        logger.info("Correction learning completed")

        // Save structured learning data (privacy-safe)
        Task { @MainActor in
            await saveStructuredLearningData()
        }
    }

    /// Save structured learning data to persistent storage (PRIVACY-SAFE)
    /// NO vendor names, amounts, or dates - only correction flags and metrics!
    private func saveStructuredLearningData() async {
        guard let learningService = learningDataService,
              let result = analysisResult else {
            return
        }

        // PRIVACY: Calculate correction flags WITHOUT storing actual values
        let wasAmountCorrected = (amountDecimal != result.amount && amountDecimal != nil)
        let wasDueDateCorrected = (hasDueDate && result.dueDate != nil && dueDate != result.dueDate)
        let wasVendorCorrected = (!vendorName.isEmpty && result.vendorName != nil && vendorName != result.vendorName)

        do {
            try await learningService.saveLearningData(
                documentType: .invoice,
                wasAmountCorrected: wasAmountCorrected,
                wasDueDateCorrected: wasDueDateCorrected,
                wasVendorCorrected: wasVendorCorrected,
                amountCandidates: result.amountCandidates ?? [],
                dateCandidates: result.dateCandidates ?? [],
                vendorCandidates: result.vendorCandidates ?? [],
                amountKeywords: [],  // TODO: Extract from keyword learning service
                dateKeywords: [],
                ocrConfidence: ocrConfidence
            )
            logger.info("Privacy-safe learning data saved (no PII/financial data)")
        } catch {
            logger.error("Failed to save learning data: \(error.localizedDescription)")
            // Don't fail the save operation if learning data fails
        }
    }

    // MARK: - Formatting

    private func formatAmount(_ decimal: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "

        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? "\(decimal)"
    }

    // MARK: - Permission Management

    /// Check current permission status (proper MVVM flow via use case)
    func checkPermissions() async {
        let status = await checkPermissionsUseCase.checkPermissions()
        calendarPermissionGranted = status.calendarGranted
        notificationPermissionGranted = status.notificationsGranted
        logger.info("Permissions checked: calendar=\(status.calendarGranted), notifications=\(status.notificationsGranted)")
    }

    /// Request both permissions (proper MVVM flow via use case)
    func requestPermissions() async {
        guard !isRequestingPermissions else { return }
        isRequestingPermissions = true
        logger.info("Requesting permissions via ViewModel...")

        // Request calendar permission first
        if !calendarPermissionGranted {
            let granted = await checkPermissionsUseCase.requestCalendarPermission()
            calendarPermissionGranted = granted
            logger.info("Calendar permission result: \(granted)")
        }

        // Then request notification permission
        if !notificationPermissionGranted {
            let granted = await checkPermissionsUseCase.requestNotificationPermission()
            notificationPermissionGranted = granted
            logger.info("Notification permission result: \(granted)")
        }

        isRequestingPermissions = false
    }

    /// Check if permissions are needed
    var needsPermissions: Bool {
        !calendarPermissionGranted || !notificationPermissionGranted
    }
}
