import Foundation
import Observation

/// Manages app settings using UserDefaults.
/// Settings are local key-value pairs, not synced to backend.
@Observable
final class SettingsManager: Sendable {

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

        // Cloud analysis settings (Pro tier - Phase 1 Foundation)
        static let cloudAnalysisEnabled = "cloudAnalysisEnabled"
        static let highAccuracyMode = "highAccuracyMode"
        static let cloudVaultEnabled = "cloudVaultEnabled"

        // Recurring payments settings
        static let syncRecurringToiOSCalendar = "syncRecurringToiOSCalendar"
    }

    // MARK: - UserDefaults

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
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

            // Cloud analysis defaults (Pro tier)
            Keys.cloudAnalysisEnabled: true,  // Enabled for testing - should be opt-in in production
            Keys.highAccuracyMode: false,     // Use local-with-assist by default
            Keys.cloudVaultEnabled: false,    // Cloud backup disabled by default

            // Recurring payments defaults
            Keys.syncRecurringToiOSCalendar: false // iOS Calendar sync disabled by default (opt-in)
        ])
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

    // MARK: - Cloud Analysis Settings (Pro Tier)

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
    /// Default: false (requires explicit opt-in and Pro tier)
    var cloudAnalysisEnabled: Bool {
        get { defaults.bool(forKey: Keys.cloudAnalysisEnabled) }
        set { defaults.set(newValue, forKey: Keys.cloudAnalysisEnabled) }
    }

    /// Enable high accuracy mode (always use cloud analysis).
    /// Requires Pro subscription and cloudAnalysisEnabled.
    /// When enabled, all documents are analyzed by cloud AI.
    /// Default: false (use local-with-assist by default)
    var highAccuracyMode: Bool {
        get { defaults.bool(forKey: Keys.highAccuracyMode) }
        set { defaults.set(newValue, forKey: Keys.highAccuracyMode) }
    }

    /// Enable cloud vault for document backup.
    /// Requires Pro subscription. When enabled, documents are
    /// encrypted and synced to cloud storage.
    /// Default: false (local-only storage)
    var cloudVaultEnabled: Bool {
        get { defaults.bool(forKey: Keys.cloudVaultEnabled) }
        set { defaults.set(newValue, forKey: Keys.cloudVaultEnabled) }
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
        // Cloud analysis settings
        defaults.removeObject(forKey: Keys.cloudAnalysisEnabled)
        defaults.removeObject(forKey: Keys.highAccuracyMode)
        defaults.removeObject(forKey: Keys.cloudVaultEnabled)
        // Recurring payments settings
        defaults.removeObject(forKey: Keys.syncRecurringToiOSCalendar)
        // Note: Not resetting onboarding
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
