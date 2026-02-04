import Foundation
import Observation
import os.log

/// Manages app settings using UserDefaults and Keychain.
/// Regular settings use UserDefaults, security-sensitive settings use Keychain.
@Observable
final class SettingsManager: Sendable {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "Settings")

    // MARK: - Keys

    private enum Keys {
        static let defaultReminderOffsets = "defaultReminderOffsets"
        static let defaultCalendarId = "defaultCalendarId"
        static let useInvoicesCalendar = "useInvoicesCalendar"
        static let invoicesCalendarId = "invoicesCalendarId"
        static let addToCalendarByDefault = "addToCalendarByDefault"
        static let defaultCurrency = "defaultCurrency"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let notificationsEnabled = "notificationsEnabled"
        static let appLanguage = "appLanguage"
        static let hideSensitiveDetails = "hideSensitiveDetails"

        // Parsing settings
        static let autoFillHighConfidence = "autoFillHighConfidence"
        static let highConfidenceThreshold = "highConfidenceThreshold"
        static let reviewThreshold = "reviewThreshold"
        static let showExtractionEvidence = "showExtractionEvidence"
        static let enableVendorTemplates = "enableVendorTemplates"

        // DEPRECATED: Cloud analysis settings moved to Keychain
        // Keep for migration purposes
        static let legacyCloudAnalysisEnabled = "cloudAnalysisEnabled"
        static let legacyHighAccuracyMode = "highAccuracyMode"
        static let legacyCloudVaultEnabled = "cloudVaultEnabled"

        // Recurring payments settings
        static let syncRecurringToiOSCalendar = "syncRecurringToiOSCalendar"

        // Migration tracking
        static let keychainMigrationCompleted = "keychainMigrationCompleted"

        // UI Style settings
        static let uiStyleHome = "uiStyleHome"
        static let uiStyleOtherViews = "uiStyleOtherViews"
    }

    // MARK: - Dependencies

    private let defaults: UserDefaults
    private let keychainService: KeychainService

    init(defaults: UserDefaults = .standard, keychainService: KeychainService = KeychainService()) {
        self.defaults = defaults
        self.keychainService = keychainService
        registerDefaults()
        migrateToKeychainIfNeeded()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.defaultReminderOffsets: [7, 1, 0],
            Keys.useInvoicesCalendar: true,
            Keys.addToCalendarByDefault: false,
            Keys.defaultCurrency: "PLN",
            Keys.hasCompletedOnboarding: false,
            Keys.notificationsEnabled: true,
            Keys.appLanguage: "pl", // Default to Polish
            Keys.hideSensitiveDetails: true, // Privacy-first: hide by default

            // Parsing settings defaults
            Keys.autoFillHighConfidence: false, // User must opt-in
            Keys.highConfidenceThreshold: 0.85,
            Keys.reviewThreshold: 0.70,
            Keys.showExtractionEvidence: true,
            Keys.enableVendorTemplates: true,

            // Cloud analysis settings are now in Keychain (security-sensitive)
            // Defaults are handled in the property getters

            // Recurring payments defaults
            Keys.syncRecurringToiOSCalendar: false, // iOS Calendar sync disabled by default (opt-in)

            // UI Style defaults - Always use Midnight Aurora
            Keys.uiStyleHome: UIStyleProposal.midnightAurora.rawValue,
            Keys.uiStyleOtherViews: UIStyleProposal.midnightAurora.rawValue
        ])
    }

    // MARK: - Keychain Migration

    /// Migrates security-sensitive settings from UserDefaults to Keychain.
    /// This is a one-time migration that runs on first launch after the update.
    private func migrateToKeychainIfNeeded() {
        guard !defaults.bool(forKey: Keys.keychainMigrationCompleted) else {
            return
        }

        logger.info("Starting Keychain migration for security-sensitive settings...")

        // Migrate cloudAnalysisEnabled
        if defaults.object(forKey: Keys.legacyCloudAnalysisEnabled) != nil {
            let value = defaults.bool(forKey: Keys.legacyCloudAnalysisEnabled)
            do {
                try keychainService.save(key: KeychainService.CloudKeys.cloudAnalysisEnabled, value: value)
                defaults.removeObject(forKey: Keys.legacyCloudAnalysisEnabled)
                logger.debug("Migrated cloudAnalysisEnabled to Keychain")
            } catch {
                logger.error("Failed to migrate cloudAnalysisEnabled: \(error.localizedDescription)")
            }
        }

        // Migrate highAccuracyMode
        if defaults.object(forKey: Keys.legacyHighAccuracyMode) != nil {
            let value = defaults.bool(forKey: Keys.legacyHighAccuracyMode)
            do {
                try keychainService.save(key: KeychainService.CloudKeys.highAccuracyMode, value: value)
                defaults.removeObject(forKey: Keys.legacyHighAccuracyMode)
                logger.debug("Migrated highAccuracyMode to Keychain")
            } catch {
                logger.error("Failed to migrate highAccuracyMode: \(error.localizedDescription)")
            }
        }

        // Migrate cloudVaultEnabled
        if defaults.object(forKey: Keys.legacyCloudVaultEnabled) != nil {
            let value = defaults.bool(forKey: Keys.legacyCloudVaultEnabled)
            do {
                try keychainService.save(key: KeychainService.CloudKeys.cloudVaultEnabled, value: value)
                defaults.removeObject(forKey: Keys.legacyCloudVaultEnabled)
                logger.debug("Migrated cloudVaultEnabled to Keychain")
            } catch {
                logger.error("Failed to migrate cloudVaultEnabled: \(error.localizedDescription)")
            }
        }

        defaults.set(true, forKey: Keys.keychainMigrationCompleted)
        logger.info("Keychain migration completed")
    }

    // MARK: - Reminder Settings

    /// Default reminder offsets in days before due date (e.g., [7, 1, 0])
    var defaultReminderOffsets: [Int] {
        get { defaults.array(forKey: Keys.defaultReminderOffsets) as? [Int] ?? [7, 1, 0] }
        set { defaults.set(newValue, forKey: Keys.defaultReminderOffsets) }
    }

    /// Available reminder offset options
    static let availableReminderOffsets = [0, 1, 2, 3, 7, 14, 30]

    // MARK: - Calendar Settings

    /// ID of the default calendar to use for events
    var defaultCalendarId: String? {
        get { defaults.string(forKey: Keys.defaultCalendarId) }
        set { defaults.set(newValue, forKey: Keys.defaultCalendarId) }
    }

    /// Whether to use a dedicated "Invoices" calendar
    var useInvoicesCalendar: Bool {
        get { defaults.bool(forKey: Keys.useInvoicesCalendar) }
        set { defaults.set(newValue, forKey: Keys.useInvoicesCalendar) }
    }

    /// ID of the created "Invoices" calendar (cached)
    var invoicesCalendarId: String? {
        get { defaults.string(forKey: Keys.invoicesCalendarId) }
        set { defaults.set(newValue, forKey: Keys.invoicesCalendarId) }
    }

    /// Whether to add invoices to calendar by default
    var addToCalendarByDefault: Bool {
        get { defaults.bool(forKey: Keys.addToCalendarByDefault) }
        set { defaults.set(newValue, forKey: Keys.addToCalendarByDefault) }
    }

    // MARK: - Currency Settings

    /// Default currency for new documents
    var defaultCurrency: String {
        get { defaults.string(forKey: Keys.defaultCurrency) ?? "PLN" }
        set { defaults.set(newValue, forKey: Keys.defaultCurrency) }
    }

    /// Available currencies
    static let availableCurrencies = ["PLN", "EUR", "USD", "GBP", "CHF", "CZK"]

    // MARK: - Language Settings

    /// App language (independent of device locale)
    /// Supported: "pl" (Polish), "en" (English)
    var appLanguage: String {
        get { defaults.string(forKey: Keys.appLanguage) ?? "pl" }
        set {
            defaults.set(newValue, forKey: Keys.appLanguage)
            // Reload localization bundle when language changes
            LocalizationManager.shared.updateLanguage()
        }
    }

    /// Available app languages
    static let availableLanguages: [(code: String, name: String)] = [
        ("pl", "Polski"),
        ("en", "English")
    ]

    // MARK: - Onboarding

    /// Whether the user has completed onboarding
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    // MARK: - Notifications

    /// Whether notifications are globally enabled
    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Keys.notificationsEnabled) }
        set { defaults.set(newValue, forKey: Keys.notificationsEnabled) }
    }

    // MARK: - Privacy

    /// Hide sensitive details (vendor name, amount) in calendar events and notifications
    /// Default: true (privacy-first)
    /// When enabled, shows generic "Invoice due" instead of vendor + amount
    var hideSensitiveDetails: Bool {
        get { defaults.bool(forKey: Keys.hideSensitiveDetails) }
        set { defaults.set(newValue, forKey: Keys.hideSensitiveDetails) }
    }

    // MARK: - Parsing Settings

    /// Auto-fill fields with high confidence without requiring review
    /// Default: false (user must opt-in for reduced friction)
    var autoFillHighConfidence: Bool {
        get { defaults.bool(forKey: Keys.autoFillHighConfidence) }
        set { defaults.set(newValue, forKey: Keys.autoFillHighConfidence) }
    }

    /// Threshold for auto-fill mode (confidence >= this value)
    /// Default: 0.85 (85% confidence required for auto-fill)
    var highConfidenceThreshold: Double {
        get {
            let value = defaults.double(forKey: Keys.highConfidenceThreshold)
            return value > 0 ? value : 0.85
        }
        set { defaults.set(newValue, forKey: Keys.highConfidenceThreshold) }
    }

    /// Threshold for suggested review mode (confidence >= this value)
    /// Below this threshold, review is required
    /// Default: 0.70 (70% confidence for suggested mode)
    var reviewThreshold: Double {
        get {
            let value = defaults.double(forKey: Keys.reviewThreshold)
            return value > 0 ? value : 0.70
        }
        set { defaults.set(newValue, forKey: Keys.reviewThreshold) }
    }

    /// Show evidence indicators (document region, extraction method)
    /// Default: true
    var showExtractionEvidence: Bool {
        get { defaults.bool(forKey: Keys.showExtractionEvidence) }
        set { defaults.set(newValue, forKey: Keys.showExtractionEvidence) }
    }

    /// Enable vendor template learning and application
    /// Default: true
    var enableVendorTemplates: Bool {
        get { defaults.bool(forKey: Keys.enableVendorTemplates) }
        set { defaults.set(newValue, forKey: Keys.enableVendorTemplates) }
    }

    // MARK: - Cloud Analysis Settings (Pro Tier - Stored in Keychain)

    /// Enable cloud-based AI analysis for documents.
    ///
    /// ## User Consent and Privacy
    ///
    /// This setting controls whether OCR text can be sent to cloud for analysis.
    /// When enabled:
    /// - OCR text is sent to cloud AI (OpenAI via Firebase) for enhanced accuracy
    /// - Text is processed immediately and NOT stored on our servers
    /// - Only structured results (vendor, amount, date) are returned
    /// - All transmission is encrypted (TLS 1.3+)
    ///
    /// **Privacy Policy**:
    /// - Requires explicit user opt-in (default: false)
    /// - Requires Pro subscription
    /// - User can disable at any time
    /// - No raw document text is retained in cloud
    ///
    /// **Security Note**: Stored in Keychain (not UserDefaults) to protect
    /// user consent state from unauthorized access on compromised devices.
    ///
    /// Default: false (requires explicit opt-in and Pro tier)
    var cloudAnalysisEnabled: Bool {
        get {
            do {
                return try keychainService.loadBool(key: KeychainService.CloudKeys.cloudAnalysisEnabled) ?? false
            } catch {
                logger.error("Failed to load cloudAnalysisEnabled from Keychain: \(error.localizedDescription)")
                return false
            }
        }
        set {
            do {
                try keychainService.save(key: KeychainService.CloudKeys.cloudAnalysisEnabled, value: newValue)
            } catch {
                logger.error("Failed to save cloudAnalysisEnabled to Keychain: \(error.localizedDescription)")
            }
        }
    }

    /// Enable high accuracy mode (always use cloud analysis).
    /// Requires Pro subscription and cloudAnalysisEnabled.
    /// When enabled, all documents are analyzed by cloud AI.
    ///
    /// **Security Note**: Stored in Keychain for security.
    ///
    /// Default: false (use local-with-assist by default)
    var highAccuracyMode: Bool {
        get {
            do {
                return try keychainService.loadBool(key: KeychainService.CloudKeys.highAccuracyMode) ?? false
            } catch {
                logger.error("Failed to load highAccuracyMode from Keychain: \(error.localizedDescription)")
                return false
            }
        }
        set {
            do {
                try keychainService.save(key: KeychainService.CloudKeys.highAccuracyMode, value: newValue)
            } catch {
                logger.error("Failed to save highAccuracyMode to Keychain: \(error.localizedDescription)")
            }
        }
    }

    /// Enable cloud vault for document backup.
    /// Requires Pro subscription. When enabled, documents are
    /// encrypted and synced to cloud storage.
    ///
    /// **Security Note**: Stored in Keychain for security.
    ///
    /// Default: false (local-only storage)
    var cloudVaultEnabled: Bool {
        get {
            do {
                return try keychainService.loadBool(key: KeychainService.CloudKeys.cloudVaultEnabled) ?? false
            } catch {
                logger.error("Failed to load cloudVaultEnabled from Keychain: \(error.localizedDescription)")
                return false
            }
        }
        set {
            do {
                try keychainService.save(key: KeychainService.CloudKeys.cloudVaultEnabled, value: newValue)
            } catch {
                logger.error("Failed to save cloudVaultEnabled to Keychain: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Recurring Payments Settings

    /// Sync recurring payment instances to iOS Calendar.
    /// When enabled, expected recurring payments are added as events
    /// to the iOS Calendar for visibility outside the app.
    /// Default: false (opt-in - internal calendar view is the primary source)
    var syncRecurringToiOSCalendar: Bool {
        get { defaults.bool(forKey: Keys.syncRecurringToiOSCalendar) }
        set { defaults.set(newValue, forKey: Keys.syncRecurringToiOSCalendar) }
    }

    // MARK: - UI Style Settings

    /// UI style for the Home view
    /// Default: .defaultStyle
    var uiStyleHome: UIStyleProposal {
        get {
            // Always use Midnight Aurora style
            return .midnightAurora
        }
        set {
            // No-op: style is fixed to Midnight Aurora
        }
    }

    /// UI style for other views (Documents, Calendar, Settings, etc.)
    /// Default: .defaultStyle
    var uiStyleOtherViews: UIStyleProposal {
        get {
            // Always use Midnight Aurora style
            return .midnightAurora
        }
        set {
            // No-op: style is fixed to Midnight Aurora
        }
    }

    /// Get the UI style for a specific context
    func uiStyle(for context: UIStyleContext) -> UIStyleProposal {
        switch context {
        case .home: return uiStyleHome
        case .otherViews: return uiStyleOtherViews
        }
    }

    /// Set the UI style for a specific context
    func setUIStyle(_ style: UIStyleProposal, for context: UIStyleContext) {
        switch context {
        case .home: uiStyleHome = style
        case .otherViews: uiStyleOtherViews = style
        }
    }

    /// Determine analysis mode based on current settings
    var analysisMode: AnalysisMode {
        guard cloudAnalysisEnabled else { return .localOnly }
        return highAccuracyMode ? .alwaysCloud : .localWithCloudAssist
    }

    /// Determine review mode for a field based on confidence
    func determineReviewMode(for confidence: Double) -> ReviewMode {
        if autoFillHighConfidence && confidence >= highConfidenceThreshold {
            return .autoFilled
        } else if confidence >= reviewThreshold {
            return .suggested
        } else {
            return .required
        }
    }

    // MARK: - Reset

    /// Resets all settings to defaults
    func resetToDefaults() {
        // Reset UserDefaults settings
        defaults.removeObject(forKey: Keys.defaultReminderOffsets)
        defaults.removeObject(forKey: Keys.defaultCalendarId)
        defaults.removeObject(forKey: Keys.useInvoicesCalendar)
        defaults.removeObject(forKey: Keys.invoicesCalendarId)
        defaults.removeObject(forKey: Keys.addToCalendarByDefault)
        defaults.removeObject(forKey: Keys.defaultCurrency)
        defaults.removeObject(forKey: Keys.notificationsEnabled)
        defaults.removeObject(forKey: Keys.appLanguage)
        defaults.removeObject(forKey: Keys.hideSensitiveDetails)
        defaults.removeObject(forKey: Keys.autoFillHighConfidence)
        defaults.removeObject(forKey: Keys.highConfidenceThreshold)
        defaults.removeObject(forKey: Keys.reviewThreshold)
        defaults.removeObject(forKey: Keys.showExtractionEvidence)
        defaults.removeObject(forKey: Keys.enableVendorTemplates)
        // Recurring payments settings
        defaults.removeObject(forKey: Keys.syncRecurringToiOSCalendar)
        // UI Style settings
        defaults.removeObject(forKey: Keys.uiStyleHome)
        defaults.removeObject(forKey: Keys.uiStyleOtherViews)

        // Reset Keychain settings (security-sensitive)
        do {
            try keychainService.delete(key: KeychainService.CloudKeys.cloudAnalysisEnabled)
            try keychainService.delete(key: KeychainService.CloudKeys.highAccuracyMode)
            try keychainService.delete(key: KeychainService.CloudKeys.cloudVaultEnabled)
        } catch {
            logger.error("Failed to reset Keychain settings: \(error.localizedDescription)")
        }

        // Note: Not resetting onboarding or migration flags
        registerDefaults()
    }
}

// MARK: - Parsing Settings Struct

/// Grouped parsing settings for convenience
struct ParsingSettings: Codable, Sendable {
    var autoFillHighConfidence: Bool = false
    var highConfidenceThreshold: Double = 0.85
    var reviewThreshold: Double = 0.70
    var showExtractionEvidence: Bool = true
    var enableVendorTemplates: Bool = true

    /// Create from SettingsManager
    init(from manager: SettingsManager) {
        self.autoFillHighConfidence = manager.autoFillHighConfidence
        self.highConfidenceThreshold = manager.highConfidenceThreshold
        self.reviewThreshold = manager.reviewThreshold
        self.showExtractionEvidence = manager.showExtractionEvidence
        self.enableVendorTemplates = manager.enableVendorTemplates
    }

    /// Default settings
    init() {}

    /// Apply to SettingsManager
    func apply(to manager: SettingsManager) {
        manager.autoFillHighConfidence = autoFillHighConfidence
        manager.highConfidenceThreshold = highConfidenceThreshold
        manager.reviewThreshold = reviewThreshold
        manager.showExtractionEvidence = showExtractionEvidence
        manager.enableVendorTemplates = enableVendorTemplates
    }
}
