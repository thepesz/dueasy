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
            Keys.addToCalendarByDefault: true,
            Keys.defaultCurrency: "PLN",
            Keys.hasCompletedOnboarding: false,
            Keys.notificationsEnabled: true,
            Keys.appLanguage: "pl", // Default to Polish
            Keys.hideSensitiveDetails: true // Privacy-first: hide by default
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
        // Note: Not resetting onboarding
        registerDefaults()
    }
}
