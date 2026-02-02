import Foundation
import UIKit
import Observation
import os.log

/// ViewModel for the document review screen.
/// Handles OCR processing, field editing, feedback recording, and document finalization.
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
    var nip: String = ""
    var bankAccountNumber: String = ""
    var notes: String = ""

    // Amount selection - all detected amounts for dropdown
    var suggestedAmounts: [(value: Decimal, context: String)] = []
    var selectedAmountIndex: Int = 0

    // Reminder settings
    var reminderOffsets: Set<Int> = []

    // Calendar settings
    var addToCalendar: Bool = false // Will be initialized from SettingsManager

    // Payment status
    var markAsPaid: Bool = false

    // Recurring payment settings
    var isRecurringPayment: Bool = false
    var recurringToleranceDays: Int = 3
    var showRecurringCategoryWarning: Bool = false
    var recurringCategoryWarningMessage: String = ""
    var isCreatingRecurringTemplate: Bool = false

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

    // MARK: - Field Candidates (for alternatives UI)

    /// Vendor name extraction candidates
    var vendorCandidates: [ExtractionCandidate] = []

    /// Amount extraction candidates
    var amountCandidates: [ExtractionCandidate] = []

    /// Due date extraction candidates
    var dateCandidates: [DateCandidate] = []

    /// Document number extraction candidates
    var documentNumberCandidates: [ExtractionCandidate] = []

    /// NIP extraction candidates
    var nipCandidates: [ExtractionCandidate] = []

    /// Bank account extraction candidates
    var bankAccountCandidates: [ExtractionCandidate] = []

    // MARK: - Review Modes (per field)

    var vendorReviewMode: ReviewMode = .suggested
    var amountReviewMode: ReviewMode = .suggested
    var dueDateReviewMode: ReviewMode = .suggested
    var documentNumberReviewMode: ReviewMode = .suggested
    var nipReviewMode: ReviewMode = .suggested
    var bankAccountReviewMode: ReviewMode = .suggested

    // MARK: - Original Values (for correction detection)

    private var originalVendorName: String?
    private var originalAmount: Decimal?
    private var originalDueDate: Date?
    private var originalDocumentNumber: String?
    private var originalNIP: String?
    private var originalBankAccount: String?

    // MARK: - Review Timing

    private var reviewStartTime: Date?

    // MARK: - Dependencies

    private let document: FinanceDocument
    private let extractUseCase: ExtractAndSuggestFieldsUseCase
    private let finalizeUseCase: FinalizeInvoiceUseCase
    private let checkPermissionsUseCase: CheckPermissionsUseCase
    private let settingsManager: SettingsManager
    private let keywordLearningService: KeywordLearningService?
    private let learningDataService: LearningDataService?
    private let vendorTemplateService: VendorTemplateService?
    private let createRecurringTemplateUseCase: CreateRecurringTemplateFromDocumentUseCase?
    private let vendorFingerprintService: VendorFingerprintServiceProtocol?
    private let documentClassifierService: DocumentClassifierServiceProtocol?

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

    /// Whether to show extraction evidence in UI
    var showExtractionEvidence: Bool {
        settingsManager.showExtractionEvidence
    }

    /// Evidence bounding box for vendor field
    var vendorEvidence: BoundingBox? {
        analysisResult?.vendorEvidence
    }

    /// Evidence bounding box for amount field
    var amountEvidence: BoundingBox? {
        analysisResult?.amountEvidence
    }

    /// Evidence bounding box for due date field
    var dueDateEvidence: BoundingBox? {
        analysisResult?.dueDateEvidence
    }

    /// Evidence bounding box for document number field
    var documentNumberEvidence: BoundingBox? {
        analysisResult?.documentNumberEvidence
    }

    /// Field confidence for vendor
    var vendorConfidence: Double {
        analysisResult?.fieldConfidences?.vendorName ?? 0.0
    }

    /// Field confidence for amount
    var amountConfidence: Double {
        analysisResult?.fieldConfidences?.amount ?? 0.0
    }

    /// Field confidence for due date
    var dueDateConfidence: Double {
        analysisResult?.fieldConfidences?.dueDate ?? 0.0
    }

    /// Field confidence for document number
    var documentNumberConfidence: Double {
        analysisResult?.fieldConfidences?.documentNumber ?? 0.0
    }

    /// Field confidence for NIP
    var nipConfidence: Double {
        analysisResult?.fieldConfidences?.nip ?? 0.0
    }

    /// Field confidence for bank account
    var bankAccountConfidence: Double {
        analysisResult?.fieldConfidences?.bankAccount ?? 0.0
    }

    /// Evidence bounding box for NIP field
    var nipEvidence: BoundingBox? {
        analysisResult?.nipEvidence
    }

    /// Evidence bounding box for bank account field
    var bankAccountEvidence: BoundingBox? {
        analysisResult?.bankAccountEvidence
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
        learningDataService: LearningDataService? = nil,
        vendorTemplateService: VendorTemplateService? = nil,
        createRecurringTemplateUseCase: CreateRecurringTemplateFromDocumentUseCase? = nil,
        vendorFingerprintService: VendorFingerprintServiceProtocol? = nil,
        documentClassifierService: DocumentClassifierServiceProtocol? = nil
    ) {
        self.document = document
        self.images = images
        self.extractUseCase = extractUseCase
        self.finalizeUseCase = finalizeUseCase
        self.checkPermissionsUseCase = checkPermissionsUseCase
        self.settingsManager = settingsManager
        self.keywordLearningService = keywordLearningService
        self.learningDataService = learningDataService
        self.vendorTemplateService = vendorTemplateService
        self.createRecurringTemplateUseCase = createRecurringTemplateUseCase
        self.vendorFingerprintService = vendorFingerprintService
        self.documentClassifierService = documentClassifierService

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
        reviewStartTime = Date()

        do {
            var result = try await extractUseCase.execute(
                images: images,
                documentType: document.type
            )

            // Apply vendor template if available and enabled
            if settingsManager.enableVendorTemplates,
               let nip = result.vendorNIP,
               let templateService = vendorTemplateService {
                result = templateService.applyTemplates(vendorNIP: nip, to: result)
                logger.info("Applied vendor template for NIP: \(PrivacyLogger.sanitizeNIP(nip))")
            }

            analysisResult = result
            ocrConfidence = result.overallConfidence
            ocrText = result.rawOCRText ?? "" // Store for keyword learning

            // PRIVACY: Only log metrics, not actual data (PII + financial)
            logger.info("OCR/Parsing result: hasVendor=\(result.vendorName != nil), hasAmount=\(result.amount != nil), hasDueDate=\(result.dueDate != nil), confidence=\(result.overallConfidence)")

            // Populate fields and determine review modes
            populateFieldsFromResult(result)

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

    /// Populate fields from analysis result and set review modes
    private func populateFieldsFromResult(_ result: DocumentAnalysisResult) {
        // Vendor name
        if let vendor = result.vendorName, !vendor.isEmpty {
            vendorName = vendor
            originalVendorName = vendor
            vendorReviewMode = settingsManager.determineReviewMode(for: vendorConfidence)
            logger.debug("Set vendor with confidence \(self.vendorConfidence), mode: \(self.vendorReviewMode.rawValue)")
        }

        // Vendor address
        if let address = result.vendorAddress, !address.isEmpty {
            vendorAddress = address
        }

        // Amount
        if let extractedAmount = result.amount {
            amount = formatAmount(extractedAmount)
            originalAmount = extractedAmount
            amountReviewMode = settingsManager.determineReviewMode(for: amountConfidence)
            logger.debug("Set amount with confidence \(self.amountConfidence), mode: \(self.amountReviewMode.rawValue)")
        }

        // Store all suggested amounts for dropdown
        self.suggestedAmounts = result.suggestedAmounts.map { ($0.0, $0.1) }
        self.selectedAmountIndex = 0
        logger.info("Found \(self.suggestedAmounts.count) suggested amounts")

        // Currency
        if let extractedCurrency = result.currency {
            currency = extractedCurrency
        }

        // Due date
        if let extractedDate = result.dueDate {
            dueDate = extractedDate
            originalDueDate = extractedDate
            hasDueDate = true
            dueDateReviewMode = settingsManager.determineReviewMode(for: dueDateConfidence)
            checkDueDateWarning()
            logger.debug("Set dueDate with confidence \(self.dueDateConfidence), mode: \(self.dueDateReviewMode.rawValue)")
        }

        // Document number
        if let number = result.documentNumber, !number.isEmpty {
            documentNumber = number
            originalDocumentNumber = number
            documentNumberReviewMode = settingsManager.determineReviewMode(for: documentNumberConfidence)
        }

        // NIP
        if let extractedNIP = result.vendorNIP, !extractedNIP.isEmpty {
            nip = extractedNIP
            originalNIP = extractedNIP
            nipReviewMode = settingsManager.determineReviewMode(for: nipConfidence)
        }

        // Bank account
        if let bankAccount = result.bankAccountNumber, !bankAccount.isEmpty {
            bankAccountNumber = bankAccount
            originalBankAccount = bankAccount
            bankAccountReviewMode = settingsManager.determineReviewMode(for: bankAccountConfidence)
        }

        // Store candidates for alternatives UI
        // Note: Converting from result candidates to ExtractionCandidate for UI
        buildCandidatesFromResult(result)
    }

    /// Build extraction candidates for alternatives UI
    private func buildCandidatesFromResult(_ result: DocumentAnalysisResult) {
        // Vendor candidates
        if let candidates = result.vendorCandidates {
            vendorCandidates = candidates.map { candidate in
                ExtractionCandidate(
                    value: candidate.name,
                    confidence: candidate.confidence,
                    bbox: candidate.lineBBox,
                    method: candidate.extractionMethod ?? .patternMatching,
                    source: candidate.extractionSource ?? candidate.matchedPattern
                )
            }
        }

        // Date candidates
        if let candidates = result.dateCandidates {
            dateCandidates = candidates
        }

        // Amount candidates - build from suggestedAmounts and amountCandidates
        if let candidates = result.amountCandidates {
            amountCandidates = candidates.map { candidate in
                ExtractionCandidate(
                    value: formatAmount(candidate.value),
                    confidence: candidate.confidence,
                    bbox: candidate.lineBBox,
                    method: candidate.extractionMethod ?? .patternMatching,
                    source: candidate.extractionSource ?? candidate.context
                )
            }
        }

        // NIP candidates
        if let candidates = result.nipCandidates {
            nipCandidates = candidates.map { candidate in
                ExtractionCandidate(
                    value: candidate.value,
                    confidence: candidate.confidence,
                    bbox: candidate.lineBBox,
                    method: candidate.extractionMethod,
                    source: candidate.extractionSource
                )
            }
        }

        // Document number candidates
        if let candidates = result.documentNumberCandidates {
            documentNumberCandidates = candidates
        }

        // Bank account candidates
        if let candidates = result.bankAccountCandidates {
            bankAccountCandidates = candidates.map { candidate in
                ExtractionCandidate(
                    value: candidate.value,
                    confidence: candidate.confidence,
                    bbox: candidate.lineBBox,
                    method: candidate.extractionMethod,
                    source: candidate.extractionSource
                )
            }
        }

        // Log candidate counts for debugging alternatives UI
        PrivacyLogger.parsing.info("Populating ViewModel fields: vendorCandidates=\(self.vendorCandidates.count), amountCandidates=\(self.amountCandidates.count), dateCandidates=\(self.dateCandidates.count), nipCandidates=\(self.nipCandidates.count), docNumCandidates=\(self.documentNumberCandidates.count), bankCandidates=\(self.bankAccountCandidates.count)")
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

        // Record parsing feedback (privacy-first)
        recordParsingFeedback()

        // Record vendor template learning
        recordVendorTemplateLearning()

        do {
            try await finalizeUseCase.execute(
                document: document,
                title: vendorName,
                vendorAddress: vendorAddress.isEmpty ? nil : vendorAddress,
                vendorNIP: nip.isEmpty ? nil : nip,
                amount: finalAmount,
                currency: currency,
                dueDate: finalDueDate,
                documentNumber: documentNumber.isEmpty ? nil : documentNumber,
                bankAccountNumber: bankAccountNumber.isEmpty ? nil : bankAccountNumber,
                notes: notes.isEmpty ? nil : notes,
                reminderOffsets: Array(reminderOffsets).sorted(by: >),
                skipCalendar: !addToCalendar
            )

            // Mark as paid if requested
            if markAsPaid {
                document.status = .paid
                logger.info("Document marked as paid")
            }

            // Create recurring template if enabled
            if isRecurringPayment {
                await createRecurringTemplate()
            }

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
        // PRIVACY: Don't log actual amount or context (may contain invoice text)
        logger.info("Selected amount candidate #\(index) (value hidden for privacy)")
    }

    /// Called when user selects an alternative vendor from the alternatives row
    func selectVendorAlternative(_ candidate: ExtractionCandidate) {
        vendorName = candidate.value
        logger.info("Selected vendor alternative from \(candidate.source)")
    }

    /// Called when user selects an alternative date from the alternatives row
    func selectDateAlternative(_ candidate: DateCandidate) {
        dueDate = candidate.date
        checkDueDateWarning()
        logger.info("Selected date alternative: \(candidate.scoreReason)")
    }

    /// Called when user selects an alternative NIP from the alternatives row
    func selectNIPAlternative(_ candidate: ExtractionCandidate) {
        nip = candidate.value
        logger.info("Selected NIP alternative from \(candidate.source)")
    }

    /// Called when user selects an alternative document number from the alternatives row
    func selectDocumentNumberAlternative(_ candidate: ExtractionCandidate) {
        documentNumber = candidate.value
        logger.info("Selected document number alternative from \(candidate.source)")
    }

    /// Called when user selects an alternative bank account from the alternatives row
    func selectBankAccountAlternative(_ candidate: ExtractionCandidate) {
        bankAccountNumber = candidate.value
        logger.info("Selected bank account alternative from \(candidate.source)")
    }

    /// Record when user selects an alternative (non-first choice) for learning
    func recordAlternativeSelection(
        field: FieldType,
        selectedCandidate: ExtractionCandidate,
        alternativeIndex: Int?
    ) {
        // PRIVACY: Log only metrics, not actual values
        PrivacyLogger.parsing.info("User selected alternative for \(field.rawValue): index=\(alternativeIndex ?? -1), confidence=\(selectedCandidate.confidence), method=\(selectedCandidate.method.rawValue)")

        // If vendor template learning is enabled, update template with selected alternative
        if let nip = analysisResult?.vendorNIP, let templateService = vendorTemplateService {
            let wasFirstChoice = alternativeIndex == 0 || alternativeIndex == nil

            templateService.recordAlternativeSelection(
                vendorNIP: nip,
                vendorName: vendorName,
                field: field,
                selectedAlternative: selectedCandidate,
                wasFirstChoice: wasFirstChoice
            )
        }
    }

    func clearError() {
        error = nil
    }

    // MARK: - Recurring Payment

    /// Toggles recurring payment and checks for category warnings
    func toggleRecurringPayment(_ enabled: Bool) {
        isRecurringPayment = enabled

        if enabled {
            checkRecurringCategoryWarning()
        } else {
            showRecurringCategoryWarning = false
            recurringCategoryWarningMessage = ""
        }
    }

    /// Checks if the document category should show a warning for recurring
    private func checkRecurringCategoryWarning() {
        guard let classifier = documentClassifierService else {
            showRecurringCategoryWarning = false
            return
        }

        let classification = classifier.classify(
            vendorName: vendorName,
            ocrText: ocrText,
            amount: amountDecimal
        )

        // Update document category
        document.documentCategory = classification.category

        // Check if this is a risky category
        if classification.category.isHardRejectedForAutoDetection {
            showRecurringCategoryWarning = true
            recurringCategoryWarningMessage = L10n.Recurring.warningFuelRetail.localized
        } else if classification.category == .unknown && classification.confidence < 0.3 {
            showRecurringCategoryWarning = true
            recurringCategoryWarningMessage = L10n.Recurring.warningNoPattern.localized
        } else {
            showRecurringCategoryWarning = false
            recurringCategoryWarningMessage = ""
        }
    }

    /// Creates a recurring template after document is saved
    private func createRecurringTemplate() async {
        guard let useCase = createRecurringTemplateUseCase else {
            logger.warning("CreateRecurringTemplateUseCase not available")
            return
        }

        isCreatingRecurringTemplate = true

        do {
            // Generate vendor fingerprint
            if let fingerprintService = vendorFingerprintService {
                let fingerprint = fingerprintService.generateFingerprint(
                    vendorName: vendorName,
                    nip: nip.isEmpty ? nil : nip
                )
                document.vendorFingerprint = fingerprint
            }

            let result = try await useCase.execute(
                document: document,
                reminderOffsets: Array(reminderOffsets).sorted(by: >),
                toleranceDays: recurringToleranceDays
            )

            logger.info("Created recurring template: \(result.template.id), instances: \(result.instances.count)")

            if let warning = result.categoryWarning {
                logger.warning("Recurring category warning: \(warning.message)")
            }
        } catch {
            logger.error("Failed to create recurring template: \(error.localizedDescription)")
            // Don't fail the save - recurring is optional
        }

        isCreatingRecurringTemplate = false
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
        // Use KeywordLearningService.FieldType for compatibility with the learning service
        if let autoAmount = result.amount,
           let manualAmount = amountDecimal,
           autoAmount != manualAmount {
            logger.info("Amount was corrected (values hidden for privacy)")
            learningService.learnFromCorrection(
                correctedValue: amount,
                ocrText: ocrText,
                fieldType: KeywordLearningService.FieldType.amount
            )
        } else if result.amount == nil && self.amountDecimal != nil {
            // Amount was added manually (OCR missed it)
            logger.info("Amount was added manually (value hidden for privacy)")
            learningService.learnFromCorrection(
                correctedValue: amount,
                ocrText: ocrText,
                fieldType: KeywordLearningService.FieldType.amount
            )
        }

        // Check if vendor was corrected
        let autoVendor = result.vendorName ?? ""
        let manualVendor = vendorName.trimmingCharacters(in: .whitespaces)
        if autoVendor != manualVendor && !manualVendor.isEmpty {
            logger.info("Vendor was corrected (values hidden for privacy)")
            learningService.learnFromCorrection(
                correctedValue: manualVendor,
                ocrText: ocrText,
                fieldType: KeywordLearningService.FieldType.vendor
            )
        }

        // Check if invoice number was corrected
        let autoNumber = result.documentNumber ?? ""
        let manualNumber = documentNumber.trimmingCharacters(in: .whitespaces)
        if autoNumber != manualNumber && !manualNumber.isEmpty {
            logger.info("Invoice number was corrected (values hidden for privacy)")
            // Use KeywordLearningService.FieldType.invoiceNumber for compatibility
            learningService.learnFromCorrection(
                correctedValue: manualNumber,
                ocrText: ocrText,
                fieldType: KeywordLearningService.FieldType.invoiceNumber
            )
        }

        // Check if due date was corrected
        if let autoDueDate = result.dueDate {
            let calendar = Calendar.current
            if !calendar.isDate(autoDueDate, inSameDayAs: self.dueDate) {
                logger.info("Due date was corrected (values hidden for privacy)")
                // Learn from the date string in context
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "dd.MM.yyyy"
                let dateString = dateFormatter.string(from: self.dueDate)
                learningService.learnFromCorrection(
                    correctedValue: dateString,
                    ocrText: ocrText,
                    fieldType: KeywordLearningService.FieldType.dueDate
                )
            }
        }

        logger.info("Correction learning completed")

        // Save structured learning data (privacy-safe)
        Task { @MainActor in
            await saveStructuredLearningData()
        }
    }

    /// Record parsing feedback for analytics (privacy-first)
    private func recordParsingFeedback() {
        guard let result = analysisResult,
              let templateService = vendorTemplateService else {
            return
        }

        let reviewDuration: TimeInterval?
        if let startTime = reviewStartTime {
            reviewDuration = Date().timeIntervalSince(startTime)
        } else {
            reviewDuration = nil
        }

        // Build field corrections
        var corrections: [FieldCorrection] = []

        // Vendor correction
        let vendorCorrected = originalVendorName != nil && vendorName != originalVendorName
        corrections.append(FieldCorrection(
            field: .vendor,
            correctedValue: vendorName,
            originalValue: originalVendorName,
            evidence: vendorEvidence,
            region: regionFromEvidence(vendorEvidence),
            wasCorrected: vendorCorrected,
            reviewMode: vendorReviewMode
        ))

        // Amount correction
        let amountCorrected = originalAmount != nil && amountDecimal != originalAmount
        corrections.append(FieldCorrection(
            field: .amount,
            correctedValue: amount,
            originalValue: originalAmount != nil ? formatAmount(originalAmount!) : nil,
            evidence: amountEvidence,
            region: regionFromEvidence(amountEvidence),
            alternativeIndex: selectedAmountIndex > 0 ? selectedAmountIndex : nil,
            wasCorrected: amountCorrected,
            reviewMode: amountReviewMode
        ))

        // Due date correction
        let dueDateCorrected = originalDueDate != nil && !Calendar.current.isDate(dueDate, inSameDayAs: originalDueDate!)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        corrections.append(FieldCorrection(
            field: .dueDate,
            correctedValue: dateFormatter.string(from: dueDate),
            originalValue: originalDueDate != nil ? dateFormatter.string(from: originalDueDate!) : nil,
            evidence: dueDateEvidence,
            region: regionFromEvidence(dueDateEvidence),
            wasCorrected: dueDateCorrected,
            reviewMode: dueDateReviewMode
        ))

        // Document number correction
        let docNumCorrected = originalDocumentNumber != nil && documentNumber != originalDocumentNumber
        corrections.append(FieldCorrection(
            field: .documentNumber,
            correctedValue: documentNumber,
            originalValue: originalDocumentNumber,
            evidence: documentNumberEvidence,
            region: regionFromEvidence(documentNumberEvidence),
            wasCorrected: docNumCorrected,
            reviewMode: documentNumberReviewMode
        ))

        // Record feedback
        templateService.recordFeedback(
            documentId: documentId,
            vendorNIP: result.vendorNIP,
            analysisResult: result,
            corrections: corrections
        )

        logger.info("Parsing feedback recorded (privacy-safe)")
    }

    /// Record vendor template learning from corrections
    private func recordVendorTemplateLearning() {
        guard settingsManager.enableVendorTemplates,
              let result = analysisResult,
              let nip = result.vendorNIP,
              let templateService = vendorTemplateService else {
            return
        }

        // Only learn if there were corrections
        let vendorCorrected = originalVendorName != nil && vendorName != originalVendorName
        let amountCorrected = originalAmount != nil && amountDecimal != originalAmount
        let dueDateCorrected = originalDueDate != nil && !Calendar.current.isDate(dueDate, inSameDayAs: originalDueDate!)
        let docNumCorrected = originalDocumentNumber != nil && documentNumber != originalDocumentNumber

        if vendorCorrected {
            templateService.recordCorrection(
                vendorNIP: nip,
                vendorName: vendorName,
                field: .vendor,
                correctedValue: vendorName,
                evidence: vendorEvidence,
                region: regionFromEvidence(vendorEvidence),
                anchorUsed: result.vendorExtractionMethod?.rawValue
            )
        }

        if amountCorrected, let decimal = amountDecimal {
            templateService.recordCorrection(
                vendorNIP: nip,
                vendorName: vendorName,
                field: .amount,
                correctedValue: formatAmount(decimal),
                evidence: amountEvidence,
                region: regionFromEvidence(amountEvidence),
                anchorUsed: result.amountExtractionMethod?.rawValue
            )
        }

        if dueDateCorrected {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd.MM.yyyy"
            templateService.recordCorrection(
                vendorNIP: nip,
                vendorName: vendorName,
                field: .dueDate,
                correctedValue: dateFormatter.string(from: dueDate),
                evidence: dueDateEvidence,
                region: regionFromEvidence(dueDateEvidence),
                anchorUsed: result.dueDateExtractionMethod?.rawValue
            )
        }

        if docNumCorrected {
            templateService.recordCorrection(
                vendorNIP: nip,
                vendorName: vendorName,
                field: .documentNumber,
                correctedValue: documentNumber,
                evidence: documentNumberEvidence,
                region: regionFromEvidence(documentNumberEvidence),
                anchorUsed: nil
            )
        }

        if vendorCorrected || amountCorrected || dueDateCorrected || docNumCorrected {
            logger.info("Vendor template learning recorded for NIP: \(PrivacyLogger.sanitizeNIP(nip))")
        }
    }

    /// Convert bounding box to document region
    private func regionFromEvidence(_ bbox: BoundingBox?) -> DocumentRegion? {
        guard let box = bbox else { return nil }

        let verticalIndex: Int
        let horizontalIndex: Int

        if box.centerY < 0.33 {
            verticalIndex = 0  // top
        } else if box.centerY < 0.66 {
            verticalIndex = 1  // middle
        } else {
            verticalIndex = 2  // bottom
        }

        if box.centerX < 0.33 {
            horizontalIndex = 0  // left
        } else if box.centerX < 0.66 {
            horizontalIndex = 1  // center
        } else {
            horizontalIndex = 2  // right
        }

        let regionMap: [[DocumentRegion]] = [
            [.topLeft, .topCenter, .topRight],
            [.middleLeft, .middleCenter, .middleRight],
            [.bottomLeft, .bottomCenter, .bottomRight]
        ]

        return regionMap[verticalIndex][horizontalIndex]
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
