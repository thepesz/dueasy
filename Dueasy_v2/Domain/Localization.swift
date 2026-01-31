import Foundation
import Combine

/// Localization utilities for easy access to translated strings.
/// Usage: "key".localized or String.localized("key")

extension String {
    /// Returns the localized version of the string using the key
    /// Uses the app's selected language from settings if available
    var localized: String {
        let bundle = LocalizationManager.shared.bundle
        return NSLocalizedString(self, tableName: nil, bundle: bundle, value: "", comment: "")
    }

    /// Returns the localized version with format arguments
    /// Usage: "greeting".localized(with: "John") -> "Hello, John!"
    func localized(with arguments: CVarArg...) -> String {
        String(format: self.localized, arguments: arguments)
    }

    /// Static method for localized strings
    /// Usage: String.localized("key")
    static func localized(_ key: String) -> String {
        key.localized
    }

    /// Static method for localized strings with format arguments
    /// Usage: String.localized("greeting", with: "John")
    static func localized(_ key: String, with arguments: CVarArg...) -> String {
        String(format: key.localized, arguments: arguments)
    }
}

// MARK: - Localization Keys

/// Centralized localization keys organized by feature area.
/// Using an enum with static strings ensures compile-time safety
/// and provides autocomplete support.
enum L10n {

    // MARK: - Common
    enum Common {
        static let cancel = "common.cancel"
        static let save = "common.save"
        static let delete = "common.delete"
        static let edit = "common.edit"
        static let done = "common.done"
        static let loading = "common.loading"
        static let error = "common.error"
        static let retry = "common.retry"
        static let ok = "common.ok"
        static let yes = "common.yes"
        static let no = "common.no"
        static let skip = "common.skip"
        static let continueButton = "common.continue"
        static let getStarted = "common.getStarted"
        static let documents = "common.documents"
        static let settings = "common.settings"
    }

    // MARK: - Documents
    enum Documents {
        static let title = "documents.title"
        static let searchPlaceholder = "documents.searchPlaceholder"
        static let addNew = "documents.addNew"
        static let deleteConfirmTitle = "documents.deleteConfirmTitle"
        static let deleteConfirmMessage = "documents.deleteConfirmMessage"
        static let loadingDocuments = "documents.loadingDocuments"

        // Empty states
        static let noDocumentsTitle = "documents.noDocuments.title"
        static let noDocumentsMessage = "documents.noDocuments.message"
        static let noDocumentsAction = "documents.noDocuments.action"
        static let noResultsTitle = "documents.noResults.title"
        static let noResultsMessage = "documents.noResults.message"
        static let noSearchResultsMessage = "documents.noSearchResults.message"
    }

    // MARK: - Document Types
    enum DocumentTypes {
        static let invoice = "documentType.invoice"
        static let contract = "documentType.contract"
        static let receipt = "documentType.receipt"
        static let comingSoon = "documentType.comingSoon"
    }

    // MARK: - Document Status
    enum Status {
        static let draft = "status.draft"
        static let scheduled = "status.scheduled"
        static let paid = "status.paid"
        static let archived = "status.archived"
        static let overdue = "status.overdue"
    }

    // MARK: - Filters
    enum Filters {
        static let all = "filter.all"
        static let pending = "filter.pending"
        static let scheduled = "filter.scheduled"
        static let paid = "filter.paid"
        static let overdue = "filter.overdue"
    }

    // MARK: - Add Document
    enum AddDocument {
        static let title = "addDocument.title"
        static let documentType = "addDocument.documentType"
        static let scanDocument = "addDocument.scanDocument"
        static let processing = "addDocument.processing"
    }

    // MARK: - Review Document
    enum Review {
        static let title = "review.title"
        static let analyzing = "review.analyzing"
        static let analyzingSubtitle = "review.analyzingSubtitle"
        static let lowConfidenceWarning = "review.lowConfidenceWarning"
        static let lowConfidenceSuggestion = "review.lowConfidenceSuggestion"
        static let pagesScanned = "review.pagesScanned"

        // Form fields
        static let vendorLabel = "review.vendorLabel"
        static let vendorPlaceholder = "review.vendorPlaceholder"
        static let vendorAddressLabel = "review.vendorAddressLabel"
        static let vendorAddressPlaceholder = "review.vendorAddressPlaceholder"
        static let amountLabel = "review.amountLabel"
        static let detectedAmounts = "review.detectedAmounts"
        static let currencyLabel = "review.currencyLabel"
        static let dueDateLabel = "review.dueDateLabel"
        static let dueDatePast = "review.dueDatePast"
        static let invoiceNumberLabel = "review.invoiceNumberLabel"
        static let invoiceNumberPlaceholder = "review.invoiceNumberPlaceholder"
        static let bankAccountLabel = "review.bankAccountLabel"
        static let bankAccountPlaceholder = "review.bankAccountPlaceholder"
        static let notesLabel = "review.notesLabel"
        static let notesPlaceholder = "review.notesPlaceholder"

        // Calendar
        static let addToCalendarTitle = "review.addToCalendar.title"
        static let addToCalendarDescription = "review.addToCalendar.description"

        // Reminders
        static let remindersTitle = "review.remindersTitle"
        static let remindersRequireCalendar = "review.remindersRequireCalendar"
        static let reminderDueDate = "review.reminderDueDate"
        static let reminderOneDay = "review.reminderOneDay"
        static let reminderDays = "review.reminderDays"

        // Save button
        static let saveButton = "review.saveButton"
        static let saveAndAddToCalendar = "review.saveAndAddToCalendar"
        static let saving = "review.saving"

        // Validation
        static let validationVendorRequired = "review.validation.vendorRequired"
        static let validationAmountRequired = "review.validation.amountRequired"

        // Permission prompts
        static let permissionsNeeded = "review.permissions.needed"
        static let calendarPermissionNeeded = "review.permissions.calendar"
        static let notificationPermissionNeeded = "review.permissions.notification"
        static let grantPermissions = "review.permissions.grant"
        static let saveWithoutCalendar = "review.permissions.saveWithoutCalendar"
    }

    // MARK: - Document Detail
    enum Detail {
        static let title = "detail.title"
        static let documentNumber = "detail.documentNumber"
        static let amount = "detail.amount"
        static let vendor = "detail.vendor"
        static let dueDate = "detail.dueDate"
        static let notes = "detail.notes"
        static let created = "detail.created"
        static let notSpecified = "detail.notSpecified"
        static let address = "detail.address"
        static let bankAccount = "detail.bankAccount"
        static let added = "detail.added"
        static let notAdded = "detail.notAdded"
        static let deleteMessage = "detail.deleteMessage"

        // Calendar
        static let calendar = "detail.calendar"
        static let calendarAdded = "detail.calendarAdded"
        static let calendarNotAdded = "detail.calendarNotAdded"
        static let reminders = "detail.reminders"

        // Actions
        static let markAsPaid = "detail.markAsPaid"
        static let deleting = "detail.deleting"
        static let editDocument = "detail.editDocument"
    }

    // MARK: - Due Dates
    enum DueDate {
        static let dueToday = "dueDate.today"
        static let dueTomorrow = "dueDate.tomorrow"
        static let dueInDays = "dueDate.inDays"
        static let overdueDays = "dueDate.overdueDays"
        static let overdueDay = "dueDate.overdueDay"
        static let noDate = "dueDate.noDate"
        static let daysBefore = "dueDate.daysBefore"
        static let dayBefore = "dueDate.dayBefore"
    }

    // MARK: - Settings
    enum Settings {
        static let title = "settings.title"

        // Notifications section
        static let notificationsSection = "settings.notifications.section"
        static let reminders = "settings.reminders"
        static let remindersConfigured = "settings.remindersConfigured"
        static let noReminders = "settings.noReminders"

        // Reminder settings
        static let defaultReminders = "settings.defaultReminders"
        static let remindersFooter = "settings.remindersFooter"
        static let onDueDate = "settings.onDueDate"
        static let oneDayBefore = "settings.oneDayBefore"
        static let daysBefore = "settings.daysBefore"

        // Calendar section
        static let calendarSection = "settings.calendar.section"
        static let calendar = "settings.calendar"
        static let useInvoicesCalendar = "settings.useInvoicesCalendar"
        static let usingInvoicesCalendar = "settings.usingInvoicesCalendar"
        static let usingDefaultCalendar = "settings.usingDefaultCalendar"
        static let calendarFooter = "settings.calendarFooter"

        // Defaults section
        static let defaultsSection = "settings.defaults.section"
        static let defaultCurrency = "settings.defaultCurrency"

        // About section
        static let aboutSection = "settings.about.section"
        static let aboutDuEasy = "settings.aboutDuEasy"
        static let privacy = "settings.privacy"
        static let privacySubtitle = "settings.privacySubtitle"
        static let version = "settings.version"
        static let build = "settings.build"
        static let aboutDescription = "settings.aboutDescription"

        // Permissions section
        static let permissionsSection = "settings.permissions.section"
        static let permissions = "settings.permissions"
        static let calendarPermission = "settings.calendarPermission"
        static let calendarPermissionGranted = "settings.calendarPermission.granted"
        static let calendarPermissionDenied = "settings.calendarPermission.denied"
        static let notificationPermission = "settings.notificationPermission"
        static let notificationPermissionGranted = "settings.notificationPermission.granted"
        static let notificationPermissionDenied = "settings.notificationPermission.denied"
        static let openSettings = "settings.openSettings"
        static let grantPermissions = "settings.grantPermissions"
    }

    // MARK: - Privacy
    enum Privacy {
        static let title = "privacy.title"
        static let localProcessingTitle = "privacy.localProcessing.title"
        static let localProcessingDescription = "privacy.localProcessing.description"
        static let secureStorageTitle = "privacy.secureStorage.title"
        static let secureStorageDescription = "privacy.secureStorage.description"
        static let yourDataTitle = "privacy.yourData.title"
        static let yourDataDescription = "privacy.yourData.description"
        static let noAccountTitle = "privacy.noAccount.title"
        static let noAccountDescription = "privacy.noAccount.description"
    }

    // MARK: - Onboarding
    enum Onboarding {
        static let scanTitle = "onboarding.scan.title"
        static let scanDescription = "onboarding.scan.description"
        static let calendarTitle = "onboarding.calendar.title"
        static let calendarDescription = "onboarding.calendar.description"
        static let securityTitle = "onboarding.security.title"
        static let securityDescription = "onboarding.security.description"

        // Permission page
        static let permissionsTitle = "onboarding.permissions.title"
        static let permissionsDescription = "onboarding.permissions.description"
        static let calendarPermission = "onboarding.permissions.calendar"
        static let calendarPermissionSubtitle = "onboarding.permissions.calendarSubtitle"
        static let notificationPermission = "onboarding.permissions.notification"
        static let notificationPermissionSubtitle = "onboarding.permissions.notificationSubtitle"
        static let allPermissionsGranted = "onboarding.permissions.allGranted"
        static let permissionsOptional = "onboarding.permissions.optional"
    }

    // MARK: - Errors
    enum Errors {
        // File Storage
        static let fileStorageSaveFailed = "error.fileStorage.saveFailed"
        static let fileStorageLoadFailed = "error.fileStorage.loadFailed"
        static let fileStorageDeleteFailed = "error.fileStorage.deleteFailed"
        static let fileStorageNotFound = "error.fileStorage.notFound"

        // Scanner
        static let scannerUnavailable = "error.scanner.unavailable"
        static let scannerCancelled = "error.scanner.cancelled"
        static let scannerFailed = "error.scanner.failed"
        static let cameraPermissionDenied = "error.camera.permissionDenied"

        // OCR
        static let ocrFailed = "error.ocr.failed"
        static let ocrNoTextFound = "error.ocr.noTextFound"
        static let ocrLowConfidence = "error.ocr.lowConfidence"

        // Parsing
        static let parsingFailed = "error.parsing.failed"
        static let parsingNoData = "error.parsing.noData"

        // Calendar
        static let calendarPermissionDenied = "error.calendar.permissionDenied"
        static let calendarAccessRestricted = "error.calendar.accessRestricted"
        static let calendarEventCreationFailed = "error.calendar.eventCreationFailed"
        static let calendarEventUpdateFailed = "error.calendar.eventUpdateFailed"
        static let calendarEventDeletionFailed = "error.calendar.eventDeletionFailed"
        static let calendarNotFound = "error.calendar.notFound"

        // Notifications
        static let notificationPermissionDenied = "error.notification.permissionDenied"
        static let notificationSchedulingFailed = "error.notification.schedulingFailed"
        static let notificationCancellationFailed = "error.notification.cancellationFailed"

        // Repository
        static let repositorySaveFailed = "error.repository.saveFailed"
        static let repositoryFetchFailed = "error.repository.fetchFailed"
        static let repositoryDeleteFailed = "error.repository.deleteFailed"
        static let documentNotFound = "error.document.notFound"

        // Validation
        static let validationAmountInvalid = "error.validation.amountInvalid"
        static let validationDueDateInPast = "error.validation.dueDateInPast"
        static let validationMissingField = "error.validation.missingField"

        // General
        static let unknown = "error.unknown"

        // Recovery suggestions
        static let recoveryCameraSettings = "error.recovery.cameraSettings"
        static let recoveryCalendarSettings = "error.recovery.calendarSettings"
        static let recoveryNotificationSettings = "error.recovery.notificationSettings"
        static let recoveryManualEntry = "error.recovery.manualEntry"
        static let recoveryDueDatePast = "error.recovery.dueDatePast"
    }
}

// MARK: - Localization Manager

/// Manages app language selection independent of system locale
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private var _bundle: Bundle = .main

    var bundle: Bundle {
        _bundle
    }

    private init() {
        updateLanguage()
        // Listen for language changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func languageDidChange() {
        updateLanguage()
    }

    /// Update the language bundle based on settings
    func updateLanguage() {
        let userDefaults = UserDefaults.standard
        let languageCode = userDefaults.string(forKey: "appLanguage") ?? "pl"

        // Map short codes to full locale codes for bundle path
        let localeCode: String
        switch languageCode {
        case "pl":
            localeCode = "pl"
        case "en":
            localeCode = "en"
        default:
            localeCode = "pl"
        }

        if let path = Bundle.main.path(forResource: localeCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            _bundle = bundle
            print("✅ Localization: Loaded bundle for language '\(languageCode)' from path: \(path)")
        } else {
            _bundle = .main
            print("⚠️ Localization: Could not find bundle for language '\(languageCode)', using main bundle")
        }
    }
}
