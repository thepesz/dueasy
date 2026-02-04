import Foundation

/// RevenueCat configuration constants for subscription management.
///
/// ## Setup Instructions
///
/// 1. Create a RevenueCat account at https://www.revenuecat.com
/// 2. Create an app in the RevenueCat dashboard
/// 3. Configure App Store Connect integration
/// 4. Replace the placeholder API key below with your actual key
///
/// ## Entitlement Setup
///
/// In RevenueCat dashboard, create an entitlement named "pro" and link it to:
/// - Monthly subscription product
/// - Yearly subscription product
///
/// ## Product IDs
///
/// These product IDs must match those configured in App Store Connect:
/// - Monthly: com.dueasy.pro.monthly
/// - Yearly: com.dueasy.pro.yearly
enum RevenueCatConfiguration {

    // MARK: - API Keys

    /// RevenueCat public API key for iOS.
    /// Replace with your actual API key from RevenueCat dashboard.
    /// Location: RevenueCat Dashboard -> Project -> API Keys -> Public SDK Key
    static let apiKey = "appl_YOUR_PUBLIC_API_KEY_HERE"

    // MARK: - Entitlement IDs

    /// The entitlement identifier for Pro features.
    /// This must match the entitlement name in RevenueCat dashboard.
    static let proEntitlementID = "pro"

    // MARK: - Product IDs

    /// Product IDs as configured in App Store Connect.
    /// These must match exactly with App Store Connect product identifiers.
    enum ProductIDs {
        static let monthlyPro = "com.dueasy.pro.monthly"
        static let yearlyPro = "com.dueasy.pro.yearly"
    }

    // MARK: - Offering IDs

    /// Offering identifiers for RevenueCat.
    /// These are configured in RevenueCat dashboard to group products.
    enum OfferingIDs {
        /// Default offering shown on paywall
        static let standard = "default"

        /// Special promotional offering (if any)
        static let promotional = "promo"
    }

    // MARK: - Package Types

    /// Package type identifiers used by RevenueCat.
    enum PackageTypes {
        static let monthly = "$rc_monthly"
        static let annual = "$rc_annual"
    }

    // MARK: - Debug Settings

    #if DEBUG
    /// Enable verbose logging in debug builds
    static let debugLoggingEnabled = true
    #else
    /// Disable verbose logging in release builds
    static let debugLoggingEnabled = false
    #endif

    // MARK: - Usage Limits (Informational)

    /// Monthly cloud extraction limits by tier.
    /// Note: Backend enforces actual limits; these are for UI display only.
    enum MonthlyLimits {
        static let free = 3
        static let pro = 100
    }

    // MARK: - Validation

    /// Check if the API key has been configured (not placeholder).
    static var isConfigured: Bool {
        !apiKey.contains("YOUR_PUBLIC_API_KEY")
    }

    /// Validate configuration on app launch.
    /// Logs warning if using placeholder API key.
    static func validateConfiguration() {
        if !isConfigured {
            #if DEBUG
            print("[RevenueCat] WARNING: Using placeholder API key. Subscriptions will not work.")
            print("[RevenueCat] Please configure your API key in RevenueCatConfiguration.swift")
            #endif
        }
    }
}
