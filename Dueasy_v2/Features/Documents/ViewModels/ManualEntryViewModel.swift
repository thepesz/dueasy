import Foundation
import Observation

/// ViewModel for manual document entry form.
@MainActor
@Observable
final class ManualEntryViewModel {

    // MARK: - Form State

    var vendorName = ""
    var vendorAddress = ""
    var amount = ""
    var currency = "PLN"
    var dueDate = Date()
    var documentNumber = ""
    var nip = ""
    var bankAccountNumber = ""
    var notes = ""
    var addToCalendar = false // Will be initialized from SettingsManager
    var reminderOffsets: Set<Int> = [] // Will be initialized from SettingsManager
    var markAsPaid = false
    var isRecurringPayment = false
    var recurringToleranceDays: Int = 3
    var recurringMonthsAhead: Int = 3

    // Fuzzy match state (for variable amount recurring detection)
    var showFuzzyMatchSheet: Bool = false
    var fuzzyMatchCandidates: [FuzzyMatchCandidate] = []
    var pendingFuzzyMatchResult: FuzzyMatchResult?
    var selectedFuzzyMatchTemplateId: UUID?

    // MARK: - UI State

    private(set) var isSaving = false
    private(set) var error: AppError?
    private(set) var validationErrors: [String] = []

    // MARK: - Dependencies

    private let documentType: DocumentType
    private let environment: AppEnvironment
    private let createDocumentUseCase: CreateDocumentUseCase
    private let finalizeUseCase: FinalizeInvoiceUseCase
    private let settingsManager: SettingsManager
    private let createRecurringTemplateUseCase: CreateRecurringTemplateFromDocumentUseCase
    private let vendorFingerprintService: VendorFingerprintServiceProtocol

    // MARK: - Initialization

    init(documentType: DocumentType, environment: AppEnvironment) {
        self.documentType = documentType
        self.environment = environment
        self.createDocumentUseCase = environment.makeCreateDocumentUseCase()
        self.finalizeUseCase = environment.makeFinalizeInvoiceUseCase()
        self.settingsManager = environment.settingsManager
        self.createRecurringTemplateUseCase = environment.makeCreateRecurringTemplateFromDocumentUseCase()
        self.vendorFingerprintService = environment.vendorFingerprintService

        // Load defaults from settings (single source of truth)
        self.currency = settingsManager.defaultCurrency
        self.reminderOffsets = Set(settingsManager.defaultReminderOffsets)
        self.addToCalendar = settingsManager.addToCalendarByDefault
    }

    // MARK: - Computed Properties

    var canSave: Bool {
        !vendorName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !amount.trimmingCharacters(in: .whitespaces).isEmpty &&
        parseAmount() != nil
    }

    var showDueDateWarning: Bool {
        dueDate < Calendar.current.startOfDay(for: Date())
    }

    // MARK: - Actions

    func save() async -> Bool {
        guard validate() else { return false }

        isSaving = true
        error = nil

        do {
            // Step 1: Create document
            let document = try await createDocumentUseCase.execute(
                type: documentType,
                title: vendorName.trimmingCharacters(in: .whitespaces)
            )

            // Step 2: Apply form values
            document.title = vendorName.trimmingCharacters(in: .whitespaces)
            document.vendorAddress = vendorAddress.isEmpty ? nil : vendorAddress
            document.amount = parseAmount() ?? 0
            document.currency = currency
            document.dueDate = dueDate
            document.documentNumber = documentNumber.isEmpty ? nil : documentNumber
            document.vendorNIP = nip.isEmpty ? nil : nip
            document.bankAccountNumber = bankAccountNumber.isEmpty ? nil : bankAccountNumber
            document.notes = notes.isEmpty ? nil : notes
            document.reminderOffsetsDays = Array(reminderOffsets).sorted(by: >)
            document.notificationsEnabled = addToCalendar
            document.analysisProvider = "manual"

            // Step 3: Finalize (schedule calendar/notifications)
            try await finalizeUseCase.execute(
                document: document,
                title: document.title,
                vendorAddress: document.vendorAddress,
                vendorNIP: document.vendorNIP,
                amount: document.amount,
                currency: document.currency,
                dueDate: document.dueDate ?? Date(),
                documentNumber: document.documentNumber,
                bankAccountNumber: document.bankAccountNumber,
                notes: document.notes,
                reminderOffsets: document.reminderOffsetsDays,
                skipCalendar: !addToCalendar
            )

            // Mark as paid if requested
            if markAsPaid {
                document.status = .paid
            }

            // Create recurring template if enabled
            if isRecurringPayment {
                await createRecurringTemplate(for: document)
            }

            // CRITICAL FIX: Ensure any post-finalization changes (markAsPaid, recurring linkage) are persisted.
            // FinalizeUseCase saves the document with status=.scheduled, but if markAsPaid was set,
            // we need to save again to persist the .paid status.
            if markAsPaid || isRecurringPayment {
                do {
                    try await environment.documentRepository.update(document)
                } catch {
                    // Log but don't fail - the document is already saved with core data
                    // This is a safety net for post-finalization changes
                }
            }

            isSaving = false
            return true

        } catch let appError as AppError {
            error = appError
            isSaving = false
            return false
        } catch {
            self.error = .unknown(error.localizedDescription)
            isSaving = false
            return false
        }
    }

    func clearError() {
        error = nil
    }

    func toggleReminderOffset(_ offset: Int) {
        if reminderOffsets.contains(offset) {
            reminderOffsets.remove(offset)
        } else {
            reminderOffsets.insert(offset)
        }
    }

    /// Toggles recurring payment and checks for fuzzy matches.
    /// If a fuzzy match is found (30-50% amount difference), shows confirmation dialog.
    func toggleRecurringPayment(_ enabled: Bool) {
        if enabled {
            // Check for fuzzy match when enabling recurring
            Task {
                await checkForFuzzyMatchAndEnable()
            }
        } else {
            isRecurringPayment = false
            // Clear fuzzy match state
            pendingFuzzyMatchResult = nil
            fuzzyMatchCandidates = []
            selectedFuzzyMatchTemplateId = nil
        }
    }

    /// Checks for fuzzy match candidates and either enables recurring or shows confirmation sheet.
    private func checkForFuzzyMatchAndEnable() async {
        guard let amount = parseAmount(), !vendorName.trimmingCharacters(in: .whitespaces).isEmpty else {
            // Can't check without vendor/amount - just enable
            isRecurringPayment = true
            return
        }

        do {
            // Create a FuzzyMatchCheckInput for the check (P2 improvement)
            let input = FuzzyMatchCheckInput(
                vendorName: vendorName.trimmingCharacters(in: .whitespaces),
                nip: nip.isEmpty ? nil : nip,
                amount: amount
            )

            let result = try await createRecurringTemplateUseCase.checkForFuzzyMatch(input: input)
            pendingFuzzyMatchResult = result

            switch result {
            case .noExistingTemplates, .autoCreateNew:
                // Safe to create new - no user confirmation needed
                isRecurringPayment = true

            case .exactMatch(let templateId):
                // Template already exists - link to it instead of creating new
                selectedFuzzyMatchTemplateId = templateId
                isRecurringPayment = true

            case .autoMatch(let templateId, _):
                // Amount is close enough (<30%) - auto-link without asking
                selectedFuzzyMatchTemplateId = templateId
                isRecurringPayment = true

            case .needsConfirmation(let candidates):
                // Amount is in fuzzy zone (30-50%) - show confirmation sheet
                fuzzyMatchCandidates = candidates
                showFuzzyMatchSheet = true
            }
        } catch {
            // If fuzzy check fails, still allow enabling recurring
            isRecurringPayment = true
        }
    }

    /// Called when user confirms "Same Service" - link to existing template
    func handleFuzzyMatchSameService(templateId: UUID) {
        selectedFuzzyMatchTemplateId = templateId
        isRecurringPayment = true
        showFuzzyMatchSheet = false
    }

    /// Called when user confirms "Different Service" - create new template
    func handleFuzzyMatchDifferentService() {
        selectedFuzzyMatchTemplateId = nil
        isRecurringPayment = true
        showFuzzyMatchSheet = false
    }

    /// Called when user cancels the fuzzy match sheet
    func handleFuzzyMatchCancel() {
        isRecurringPayment = false
        showFuzzyMatchSheet = false
        pendingFuzzyMatchResult = nil
        fuzzyMatchCandidates = []
        selectedFuzzyMatchTemplateId = nil
    }

    // MARK: - Recurring Template

    private func createRecurringTemplate(for document: FinanceDocument) async {
        do {
            // Generate vendor fingerprint with amount
            let fingerprint = vendorFingerprintService.generateFingerprint(
                vendorName: vendorName,
                nip: nip.isEmpty ? nil : nip,
                amount: document.amount
            )
            document.vendorFingerprint = fingerprint

            // Check if we should link to existing template (fuzzy match selected)
            if let templateId = selectedFuzzyMatchTemplateId {
                // Link to existing template (same service path)
                _ = try await createRecurringTemplateUseCase.linkToExistingTemplate(
                    document: document,
                    templateId: templateId,
                    reminderOffsets: Array(reminderOffsets).sorted(by: >),
                    toleranceDays: recurringToleranceDays,
                    monthsAhead: recurringMonthsAhead
                )
            } else {
                // Create new template
                _ = try await createRecurringTemplateUseCase.execute(
                    document: document,
                    reminderOffsets: Array(reminderOffsets).sorted(by: >),
                    toleranceDays: recurringToleranceDays,
                    monthsAhead: recurringMonthsAhead
                )
            }
        } catch {
            // Don't fail the save - recurring is optional
            // The document is already saved at this point
        }
    }

    // MARK: - Private Helpers

    private func validate() -> Bool {
        validationErrors = []

        if vendorName.trimmingCharacters(in: .whitespaces).isEmpty {
            validationErrors.append(L10n.Review.validationVendorRequired.localized)
        }

        if amount.trimmingCharacters(in: .whitespaces).isEmpty {
            validationErrors.append(L10n.Review.validationAmountRequired.localized)
        } else if parseAmount() == nil {
            validationErrors.append(L10n.Errors.validationAmountInvalid.localized)
        }

        return validationErrors.isEmpty
    }

    func parseAmount() -> Decimal? {
        let cleaned = amount
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)

        return Decimal(string: cleaned)
    }
}
