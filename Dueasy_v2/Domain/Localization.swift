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
        static let add = "common.add"
        static let statistics = "common.statistics"
        static let comingSoon = "common.comingSoon"
        static let comingSoonMessage = "common.comingSoonMessage"
        static let on = "common.on"
        static let off = "common.off"
        static let actions = "common.actions"
    }

    // MARK: - Documents
    enum Documents {
        static let title = "documents.title"
        static let searchPlaceholder = "documents.searchPlaceholder"
        static let addNew = "documents.addNew"
        static let deleteConfirmTitle = "documents.deleteConfirmTitle"
        static let deleteConfirmMessage = "documents.deleteConfirmMessage"
        static let loadingDocuments = "documents.loadingDocuments"

        // Two-step deletion (iOS Calendar style)
        static let deleteInvoiceTitle = "documents.deleteInvoice.title"
        static let deleteInvoiceMessage = "documents.deleteInvoice.message"

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
        static let selectInputMethod = "addDocument.selectInputMethod"
        static let recommended = "addDocument.recommended"

        // Input method names and descriptions
        enum InputMethod {
            static let scan = "addDocument.inputMethod.scan"
            static let scanDescription = "addDocument.inputMethod.scan.description"
            static let importPDF = "addDocument.inputMethod.importPDF"
            static let importPDFDescription = "addDocument.inputMethod.importPDF.description"
            static let importPhoto = "addDocument.inputMethod.importPhoto"
            static let importPhotoDescription = "addDocument.inputMethod.importPhoto.description"
            static let manualEntry = "addDocument.inputMethod.manualEntry"
            static let manualEntryDescription = "addDocument.inputMethod.manualEntry.description"
        }

        // Manual entry specific
        enum ManualEntry {
            static let infoTitle = "addDocument.manualEntry.infoTitle"
            static let infoDescription = "addDocument.manualEntry.infoDescription"
        }

        // Processing states
        enum Processing {
            static let extractingPDF = "addDocument.processing.extractingPDF"
            static let analyzingPhoto = "addDocument.processing.analyzingPhoto"
            static let preparingDocument = "addDocument.processing.preparingDocument"
        }
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
        static let nipLabel = "review.nipLabel"
        static let nipPlaceholder = "review.nipPlaceholder"
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

        // Mark as paid
        static let markAsPaidTitle = "review.markAsPaid.title"
        static let markAsPaidDescription = "review.markAsPaid.description"

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
        static let nip = "detail.nip"
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

    // MARK: - Edit Document
    enum Edit {
        static let title = "edit.title"
        static let vendorName = "edit.vendorName"
        static let vendorNamePlaceholder = "edit.vendorNamePlaceholder"
        static let vendorAddress = "edit.vendorAddress"
        static let vendorAddressPlaceholder = "edit.vendorAddressPlaceholder"
        static let nip = "edit.nip"
        static let nipPlaceholder = "edit.nipPlaceholder"
        static let amount = "edit.amount"
        static let amountPlaceholder = "edit.amountPlaceholder"
        static let currency = "edit.currency"
        static let dueDate = "edit.dueDate"
        static let documentNumber = "edit.documentNumber"
        static let documentNumberPlaceholder = "edit.documentNumberPlaceholder"
        static let bankAccount = "edit.bankAccount"
        static let bankAccountPlaceholder = "edit.bankAccountPlaceholder"
        static let notes = "edit.notes"
        static let notesPlaceholder = "edit.notesPlaceholder"
        static let saving = "edit.saving"
        static let required = "edit.required"
        static let optional = "edit.optional"
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

    // MARK: - Calendar View
    enum CalendarView {
        static let title = "calendar.title"
        static let today = "calendar.today"
        static let noDocuments = "calendar.noDocuments"
        static let documentsCount = "calendar.documentsCount"
        static let documentsDue = "calendar.documentsDue"
        static let loading = "calendar.loading"
        static let showRecurringOnly = "calendar.showRecurringOnly"
        static let recurringCount = "calendar.recurringCount"
        static let recurringSection = "calendar.recurringSection"
        static let documentsSection = "calendar.documentsSection"
        static let noRecurring = "calendar.noRecurring"
        static let noRecurringMessage = "calendar.noRecurringMessage"
        static let expectedPayment = "calendar.expectedPayment"
        static let matchedPayment = "calendar.matchedPayment"
        static let markAsPaid = "calendar.markAsPaid"
        static let viewDocument = "calendar.viewDocument"
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
        static let syncRecurringToiOSCalendar = "settings.syncRecurringToiOSCalendar"
        static let syncRecurringToiOSCalendarFooter = "settings.syncRecurringToiOSCalendarFooter"

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

    // MARK: - App Branding
    enum App {
        static let tagline = "app.tagline"
    }

    // MARK: - Weekdays
    enum Weekdays {
        static let monday = "weekdays.monday"
        static let tuesday = "weekdays.tuesday"
        static let wednesday = "weekdays.wednesday"
        static let thursday = "weekdays.thursday"
        static let friday = "weekdays.friday"
        static let saturday = "weekdays.saturday"
        static let sunday = "weekdays.sunday"
    }

    // MARK: - Security Settings
    enum Security {
        static let title = "security.title"
        static let section = "security.section"
        static let appLock = "security.appLock"
        static let appLockFooter = "security.appLockFooter"
        static let lockTimeout = "security.lockTimeout"
        static let lockTimeoutSection = "security.lockTimeoutSection"
        static let lockTimeoutFooter = "security.lockTimeoutFooter"
        static let biometricStatus = "security.biometricStatus"
        static let dataProtection = "security.dataProtection"
        static let biometricUnavailable = "security.biometricUnavailable"

        // Biometric types
        static let requireFaceID = "security.requireFaceID"
        static let requireTouchID = "security.requireTouchID"
        static let requirePasscode = "security.requirePasscode"
        static let protectFinancialData = "security.protectFinancialData"
        static let faceIDAvailable = "security.faceIDAvailable"
        static let touchIDAvailable = "security.touchIDAvailable"
        static let usingPasscode = "security.usingPasscode"
        static let faceIDEnabled = "security.faceIDEnabled"
        static let touchIDEnabled = "security.touchIDEnabled"
        static let passcodeEnabled = "security.passcodeEnabled"
        static let appLockDisabled = "security.appLockDisabled"

        // Lock timeout options
        static let lockImmediately = "security.lockImmediately"
        static let lockAfter1Min = "security.lockAfter1Min"
        static let lockAfter5Min = "security.lockAfter5Min"
        static let lockAfter15Min = "security.lockAfter15Min"
        static let lockAfter30Min = "security.lockAfter30Min"

        // Data protection
        static let fileProtection = "security.fileProtection"
        static let fileProtectionDesc = "security.fileProtectionDesc"
        static let noCloudBackup = "security.noCloudBackup"
        static let noCloudBackupDesc = "security.noCloudBackupDesc"
        static let privacyLogging = "security.privacyLogging"
        static let privacyLoggingDesc = "security.privacyLoggingDesc"

        // App Lock View
        static let appLocked = "security.appLocked"
        static let dataProtected = "security.dataProtected"
        static let authenticating = "security.authenticating"
        static let unlockFaceID = "security.unlockFaceID"
        static let unlockTouchID = "security.unlockTouchID"
        static let unlockPasscode = "security.unlockPasscode"
    }

    // MARK: - Language Settings
    enum Language {
        static let appLanguage = "language.appLanguage"
        static let languageFooter = "language.footer"
    }

    // MARK: - Permission Settings
    enum PermissionSettings {
        static let permissionsDeniedFooter = "permissionSettings.deniedFooter"
    }

    // MARK: - Detail View Labels
    enum DetailLabels {
        static let remindersEnabled = "detail.remindersEnabled"
    }

    // MARK: - Document Categories
    enum DocumentCategoryKeys {
        static let utility = "documentCategory.utility"
        static let telecom = "documentCategory.telecom"
        static let rent = "documentCategory.rent"
        static let insurance = "documentCategory.insurance"
        static let subscription = "documentCategory.subscription"
        static let invoiceGeneric = "documentCategory.invoiceGeneric"
        static let fuel = "documentCategory.fuel"
        static let grocery = "documentCategory.grocery"
        static let retail = "documentCategory.retail"
        static let receipt = "documentCategory.receipt"
        static let unknown = "documentCategory.unknown"

        /// Returns the localization key for a given category
        static func forCategory(_ category: DocumentCategory) -> String {
            switch category {
            case .utility: return utility
            case .telecom: return telecom
            case .rent: return rent
            case .insurance: return insurance
            case .subscription: return subscription
            case .invoiceGeneric: return invoiceGeneric
            case .fuel: return fuel
            case .grocery: return grocery
            case .retail: return retail
            case .receipt: return receipt
            case .unknown: return unknown
            }
        }
    }

    // MARK: - Recurring Payments
    enum Recurring {
        // Review screen - recurring toggle
        static let toggleTitle = "recurring.toggleTitle"
        static let toggleDescription = "recurring.toggleDescription"
        static let settingsTitle = "recurring.settingsTitle"
        static let toleranceDays = "recurring.toleranceDays"
        static let toleranceDaysDescription = "recurring.toleranceDaysDescription"
        static let warningFuelRetail = "recurring.warningFuelRetail"
        static let warningNoPattern = "recurring.warningNoPattern"

        // Recurring overview
        static let overviewTitle = "recurring.overviewTitle"
        static let templatesSection = "recurring.templatesSection"
        static let instancesSection = "recurring.instancesSection"
        static let noTemplates = "recurring.noTemplates"
        static let noTemplatesMessage = "recurring.noTemplatesMessage"
        static let noUpcoming = "recurring.noUpcoming"
        static let noUpcomingMessage = "recurring.noUpcomingMessage"
        static let templateCount = "recurring.templateCount"
        static let activeTemplates = "recurring.activeTemplates"
        static let pausedTemplates = "recurring.pausedTemplates"

        // Template detail
        static let templateDetailTitle = "recurring.templateDetailTitle"
        static let vendorLabel = "recurring.vendorLabel"
        static let dueDayLabel = "recurring.dueDayLabel"
        static let dueDayValue = "recurring.dueDayValue"
        static let toleranceLabel = "recurring.toleranceLabel"
        static let toleranceValue = "recurring.toleranceValue"
        static let remindersLabel = "recurring.remindersLabel"
        static let amountRangeLabel = "recurring.amountRangeLabel"
        static let amountRangeValue = "recurring.amountRangeValue"
        static let ibanLabel = "recurring.ibanLabel"
        static let statsLabel = "recurring.statsLabel"
        static let matchedCount = "recurring.matchedCount"
        static let paidCount = "recurring.paidCount"
        static let missedCount = "recurring.missedCount"
        static let pauseTemplate = "recurring.pauseTemplate"
        static let resumeTemplate = "recurring.resumeTemplate"
        static let deleteTemplate = "recurring.deleteTemplate"
        static let deleteTemplateConfirm = "recurring.deleteTemplateConfirm"

        // Creation source
        static let sourceManual = "recurring.source.manual"
        static let sourceAutoDetection = "recurring.source.autoDetection"
    }

    // MARK: - Recurring Instance Status
    enum RecurringInstance {
        static let expected = "recurring.instance.expected"
        static let matched = "recurring.instance.matched"
        static let paid = "recurring.instance.paid"
        static let missed = "recurring.instance.missed"
        static let cancelled = "recurring.instance.cancelled"
        static let dueIn = "recurring.instance.dueIn"
        static let dueToday = "recurring.instance.dueToday"
        static let overdue = "recurring.instance.overdue"

        /// Returns the localization key for a given status
        static func status(for status: RecurringInstanceStatus) -> String {
            switch status {
            case .expected: return expected
            case .matched: return matched
            case .paid: return paid
            case .missed: return missed
            case .cancelled: return cancelled
            }
        }
    }

    // MARK: - Recurring Suggestions
    enum RecurringSuggestions {
        static let title = "recurring.suggestionsTitle"
        static let sectionTitle = "recurring.sectionTitle"
        static let cardTitle = "recurring.suggestionCard.title"
        static let cardDescription = "recurring.suggestionCard.description"
        static let cardConfidence = "recurring.suggestionCard.confidence"
        static let accept = "recurring.suggestionCard.accept"
        static let dismiss = "recurring.suggestionCard.dismiss"
        static let snooze = "recurring.suggestionCard.snooze"
        static let noSuggestions = "recurring.noSuggestions"
        static let noSuggestionsMessage = "recurring.noSuggestionsMessage"
        static let inlineDescription = "recurring.inlineDescription"
        static let inlineDescriptionNoDueDay = "recurring.inlineDescriptionNoDueDay"
        static let moreSuggestions = "recurring.moreSuggestions"
        static let setupReminders = "recurring.setupReminders"
        static let confidence = "recurring.confidence"
        static let documentsFound = "recurring.documentsFound"
        static let typicalDueDate = "recurring.typicalDueDate"
        static let dayOfMonth = "recurring.dayOfMonth"
        static let averageAmount = "recurring.averageAmount"
        static let reminderDescription = "recurring.reminderDescription"
        static let createRecurring = "recurring.createRecurring"
        static let patternWithDueDay = "recurring.patternWithDueDay"
        static let patternNoDueDay = "recurring.patternNoDueDay"
        static let durationTitle = "recurring.durationTitle"
        static let durationDescription = "recurring.durationDescription"
        static let monthsAhead = "recurring.monthsAhead"
        static let monthsCount = "recurring.monthsCount"
        static let durationHint = "recurring.durationHint"
        static let selectedDuration = "recurring.selectedDuration"
    }

    // MARK: - Recurring Deletion
    enum RecurringDeletion {
        // Scenario 1: Document linked to recurring
        static let documentTitle = "recurring.deletion.documentTitle"
        static let documentSubtitle = "recurring.deletion.documentSubtitle"
        static let deleteOnlyThisInvoice = "recurring.deletion.deleteOnlyThisInvoice"
        static let deleteOnlyThisInvoiceDescription = "recurring.deletion.deleteOnlyThisInvoiceDescription"
        static let cancelRecurringPayments = "recurring.deletion.cancelRecurringPayments"
        static let cancelRecurringPaymentsDescription = "recurring.deletion.cancelRecurringPaymentsDescription"

        // iOS Calendar style - recurring series messages
        static let recurringSeriesTitle = "recurring.deletion.recurringSeriesTitle"
        static let recurringSeriesMessage = "recurring.deletion.recurringSeriesMessage"
        static let deleteThisOnly = "recurring.deletion.deleteThisOnly"
        static let deleteThisOnlyDescription = "recurring.deletion.deleteThisOnlyDescription"
        static let deleteAllFuture = "recurring.deletion.deleteAllFuture"
        static let deleteAllFutureDescription = "recurring.deletion.deleteAllFutureDescription"

        // Scenario 2: Instance/template deletion
        static let instanceTitle = "recurring.deletion.instanceTitle"
        static let instanceSubtitle = "recurring.deletion.instanceSubtitle"
        static let deleteThisMonthOnly = "recurring.deletion.deleteThisMonthOnly"
        static let deleteThisMonthOnlyDescription = "recurring.deletion.deleteThisMonthOnlyDescription"
        static let deleteAllFutureOccurrences = "recurring.deletion.deleteAllFutureOccurrences"
        static let deleteAllFutureOccurrencesDescription = "recurring.deletion.deleteAllFutureOccurrencesDescription"

        // Shared
        static let cancel = "recurring.deletion.cancel"
        static let cancelDescription = "recurring.deletion.cancelDescription"
        static let warning = "recurring.deletion.warning"
        static let futureInstancesCount = "recurring.deletion.futureInstancesCount"
        static let keepHistory = "recurring.deletion.keepHistory"

        // Success messages
        static let successInvoiceOnly = "recurring.deletion.successInvoiceOnly"
        static let successRecurringCancelled = "recurring.deletion.successRecurringCancelled"
        static let successThisMonthOnly = "recurring.deletion.successThisMonthOnly"
        static let successAllFuture = "recurring.deletion.successAllFuture"
    }

    // MARK: - Subscription
    enum Subscription {
        static let section = "subscription.section"
        static let upgradeTitle = "subscription.upgradeTitle"
        static let upgradeToPro = "subscription.upgradeToPro"
        static let unlockFeature = "subscription.unlockFeature"
        static let choosePlan = "subscription.choosePlan"
        static let monthly = "subscription.monthly"
        static let yearly = "subscription.yearly"
        static let perMonth = "subscription.perMonth"
        static let perYear = "subscription.perYear"
        static let cancelAnytime = "subscription.cancelAnytime"
        static let bestValue = "subscription.bestValue"
        static let bestValueBadge = "subscription.bestValueBadge"
        static let startFreeTrial = "subscription.startFreeTrial"
        static let trialInfo = "subscription.trialInfo"
        static let cancelInSettings = "subscription.cancelInSettings"
        static let termsOfService = "subscription.termsOfService"
        static let privacyPolicy = "subscription.privacyPolicy"
        static let restore = "subscription.restore"
        static let maybeLater = "subscription.maybeLater"
        static let purchaseError = "subscription.purchaseError"
        static let loadingStatus = "subscription.loadingStatus"
        static let manageSubscription = "subscription.manageSubscription"
        static let upgradeFooter = "subscription.upgradeFooter"
        static let willRenewOn = "subscription.willRenewOn"
        static let expiresOn = "subscription.expiresOn"
        static let freeTrial = "subscription.freeTrial"
        static let paymentIssue = "subscription.paymentIssue"
        static let active = "subscription.active"
        static let inactive = "subscription.inactive"
        static let localOnly = "subscription.localOnly"
        static let status = "subscription.status"
        static let tier = "subscription.tier"
        static let plan = "subscription.plan"
        static let expires = "subscription.expires"
        static let subscribed = "subscription.subscribed"
        static let autoRenew = "subscription.autoRenew"
        static let trialPeriod = "subscription.trialPeriod"
        static let details = "subscription.details"
        static let manageInAppStore = "subscription.manageInAppStore"
        static let cancelSubscription = "subscription.cancelSubscription"
        static let cancelFooter = "subscription.cancelFooter"
    }

    // MARK: - Home Screen (Glance Dashboard)
    enum Home {
        static let title = "home.title"
        static let statusOffline = "home.status.offline"
        static let statusPro = "home.status.pro"

        // Hero Card
        static let dueIn7Days = "home.hero.dueIn7Days"
        static let invoicesCount = "home.hero.invoicesCount"
        static let nextDue = "home.hero.nextDue"
        static let noUpcoming = "home.hero.noUpcoming"
        static let allSet = "home.hero.allSet"

        // Status Capsules
        static let overdue = "home.capsule.overdue"
        static let dueSoon = "home.capsule.dueSoon"

        // Overdue Tile
        static let overdueTitle = "home.overdue.title"
        static let allClear = "home.overdue.allClear"
        static let oldestOverdue = "home.overdue.oldest"
        static let review = "home.overdue.review"
        static let check = "home.overdue.check"

        // Recurring Tile
        static let recurringTitle = "home.recurring.title"
        static let activeCount = "home.recurring.active"
        static let nextRecurring = "home.recurring.next"
        static let missingCount = "home.recurring.missing"
        static let manage = "home.recurring.manage"
        static let setupRecurring = "home.recurring.setup"

        // Next Payments
        static let nextPayments = "home.nextPayments.title"
        static let seeAllUpcoming = "home.nextPayments.seeAll"
        static let dueTodayLabel = "home.nextPayments.dueToday"
        static let dueInDaysLabel = "home.nextPayments.dueInDays"
        static let overdueDaysLabel = "home.nextPayments.overdueDays"

        // Month Summary (Donut)
        static let thisMonth = "home.month.title"
        static let paymentStatus = "home.month.paymentStatus"
        static let unpaidTotal = "home.month.unpaidTotal"

        // Donut segment labels
        enum Donut {
            static let paid = "home.donut.paid"
            static let due = "home.donut.due"
            static let overdue = "home.donut.overdue"
        }

        // Empty State
        static let noPaymentsTitle = "home.empty.title"
        static let noPaymentsMessage = "home.empty.message"
        static let goToScan = "home.empty.goToScan"
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
            #if DEBUG
            print("Localization: Loaded bundle for language '\(languageCode)' from path: \(path)")
            #endif
        } else {
            _bundle = .main
            #if DEBUG
            print("Localization: Could not find bundle for language '\(languageCode)', using main bundle")
            #endif
        }
    }
}
