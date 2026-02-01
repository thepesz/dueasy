import Foundation

/// Subscription and entitlement service for premium features.
/// Manages App Store subscription state and Pro tier access.
///
/// Iteration 1: No-op implementation (free tier only).
/// Iteration 2: StoreKit 2 integration with server-side receipt validation.
///
/// Monetization tiers:
/// - Free: Local-only analysis, basic features
/// - Pro: Cloud AI analysis, cloud vault, enhanced accuracy
protocol SubscriptionServiceProtocol: Sendable {

    /// Check if user has active Pro subscription.
    /// Returns true if user has valid, non-expired Pro entitlement.
    var hasProSubscription: Bool { get async }

    /// Current subscription status with details.
    var subscriptionStatus: SubscriptionStatus { get async }

    /// Available subscription products.
    /// Returns products fetched from App Store Connect.
    var availableProducts: [SubscriptionProduct] { get async }

    /// Fetch and refresh subscription status from App Store.
    /// - Returns: Updated subscription status
    /// - Throws: `SubscriptionError` on failure
    func refreshStatus() async throws -> SubscriptionStatus

    /// Purchase a subscription product.
    /// - Parameter productId: The product identifier to purchase
    /// - Returns: Updated subscription status after purchase
    /// - Throws: `SubscriptionError` on failure
    func purchase(productId: String) async throws -> SubscriptionStatus

    /// Restore previous purchases.
    /// Used when user reinstalls app or switches devices.
    /// - Returns: Updated subscription status
    /// - Throws: `SubscriptionError` on failure
    func restorePurchases() async throws -> SubscriptionStatus

    /// Listen for subscription status changes.
    /// Emits when subscription is purchased, renewed, or expires.
    /// - Returns: Async stream of subscription status updates
    func statusChanges() -> AsyncStream<SubscriptionStatus>
}

// MARK: - Subscription Status

/// Current subscription state and metadata.
struct SubscriptionStatus: Sendable, Equatable {

    /// Whether the subscription is currently active
    let isActive: Bool

    /// Subscription tier (free or pro)
    let tier: SubscriptionTier

    /// Expiration date (nil for free tier or lifetime)
    let expirationDate: Date?

    /// Whether subscription will auto-renew
    let willAutoRenew: Bool

    /// Product identifier of current subscription (nil for free)
    let productId: String?

    /// When the subscription was originally purchased
    let originalPurchaseDate: Date?

    /// Whether this is a trial period
    let isTrialPeriod: Bool

    /// Whether subscription is in grace period (billing issue)
    let isInGracePeriod: Bool

    /// Free tier status
    static let free = SubscriptionStatus(
        isActive: false,
        tier: .free,
        expirationDate: nil,
        willAutoRenew: false,
        productId: nil,
        originalPurchaseDate: nil,
        isTrialPeriod: false,
        isInGracePeriod: false
    )

    /// Check if subscription is about to expire (within 7 days)
    var isExpiringSoon: Bool {
        guard let expiration = expirationDate else { return false }
        let daysUntilExpiry = Calendar.current.dateComponents([.day], from: Date(), to: expiration).day ?? 0
        return daysUntilExpiry <= 7 && daysUntilExpiry > 0
    }
}

// MARK: - Subscription Tier

/// Subscription tier levels.
enum SubscriptionTier: String, Sendable, Codable {
    case free
    case pro

    var displayName: String {
        switch self {
        case .free:
            return "Free"
        case .pro:
            return "Pro"
        }
    }

    /// Features available at this tier
    var features: [TierFeature] {
        switch self {
        case .free:
            return [.localOCR, .localParsing, .unlimitedDocuments, .calendarIntegration]
        case .pro:
            return [.localOCR, .localParsing, .unlimitedDocuments, .calendarIntegration,
                    .cloudAIAnalysis, .cloudVault, .prioritySupport, .enhancedAccuracy]
        }
    }
}

/// Individual features that can be part of a tier
enum TierFeature: String, Sendable {
    case localOCR = "local_ocr"
    case localParsing = "local_parsing"
    case unlimitedDocuments = "unlimited_documents"
    case calendarIntegration = "calendar_integration"
    case cloudAIAnalysis = "cloud_ai_analysis"
    case cloudVault = "cloud_vault"
    case prioritySupport = "priority_support"
    case enhancedAccuracy = "enhanced_accuracy"

    var displayName: String {
        switch self {
        case .localOCR:
            return "On-device OCR"
        case .localParsing:
            return "Smart field extraction"
        case .unlimitedDocuments:
            return "Unlimited documents"
        case .calendarIntegration:
            return "Calendar integration"
        case .cloudAIAnalysis:
            return "AI-powered analysis"
        case .cloudVault:
            return "Cloud backup"
        case .prioritySupport:
            return "Priority support"
        case .enhancedAccuracy:
            return "Enhanced accuracy"
        }
    }
}

// MARK: - Subscription Product

/// A subscription product available for purchase.
struct SubscriptionProduct: Sendable, Identifiable {
    let id: String
    let displayName: String
    let description: String
    let displayPrice: String
    let priceValue: Decimal
    let currencyCode: String
    let subscriptionPeriod: SubscriptionPeriod
    let introductoryOffer: IntroductoryOffer?
}

/// Subscription billing period
enum SubscriptionPeriod: String, Sendable {
    case weekly
    case monthly
    case yearly

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }
}

/// Introductory offer details
struct IntroductoryOffer: Sendable {
    let displayPrice: String
    let period: SubscriptionPeriod
    let numberOfPeriods: Int
    let type: OfferType

    enum OfferType: String, Sendable {
        case freeTrial
        case payAsYouGo
        case payUpFront
    }
}

// MARK: - Subscription Errors

/// Errors specific to subscription operations.
enum SubscriptionError: LocalizedError {
    case notAvailable
    case productNotFound
    case purchaseFailed(String)
    case purchaseCancelled
    case verificationFailed
    case networkError(Error)
    case storeKitError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Subscriptions are not available"
        case .productNotFound:
            return "Subscription product not found"
        case .purchaseFailed(let reason):
            return "Purchase failed: \(reason)"
        case .purchaseCancelled:
            return "Purchase was cancelled"
        case .verificationFailed:
            return "Could not verify purchase"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .storeKitError(let message):
            return "Store error: \(message)"
        case .unknown(let message):
            return "Subscription error: \(message)"
        }
    }
}
